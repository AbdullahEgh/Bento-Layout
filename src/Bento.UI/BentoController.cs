using System.Windows.Interop;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace Bento.UI;

public sealed class BentoController : IDisposable
{
    private readonly HwndSource source;
    private readonly DesktopEvents events;
    private readonly Forms.NotifyIcon tray;
    private readonly TrayInterface trayInterface;
    private readonly WindowController native = new();
    private readonly Dictionary<string, DesktopBackdropWindow> backdrops = new();
    private readonly LayoutHistory history = new();
    private readonly Func<IReadOnlyList<AppWindow>>? windowSource;
    private readonly Func<long> clock;
    private readonly DragIntent dragIntent = new();
    private readonly SnapLease? snapLease;
    private DesktopTransition? transition;
    private BentoWindow? appWindow;
    private DropIntent intent;
    private PixelRect dropTargetBounds;
    private PixelPoint? touchPoint;
    private readonly Dictionary<long, (AppWindow Window, WindowSnapshot Snapshot)> minimizedByBento = new();
    private readonly HashSet<long> reopened = new();
    public int MinimizedCount => minimizedByBento.Count;
    private readonly HashSet<long> released = new();
    private bool automatic;
    private SessionLayoutSnapshot? lastBento;
    private SessionLayoutSnapshot? savedSession;
    private readonly ResizeHandleCache resizeHandles = new();
    private Guid? dividerSurface;
    private readonly Dictionary<string, (LayoutNode Root, PixelRect Area)> workAreaBaseline = new();
    private bool reflowing;
    public bool HasSessionSave => savedSession is not null;
    private IEnumerable<SessionWindow> SessionWindows => Windows.Select(w => new SessionWindow(w.Id, w.ProcessId, w.Minimum));
    private bool disposed;
    private string? failedMembership;
    private long? rejectedWindow;
    private sealed class PlacementFailure(long id, Exception cause) : Exception(cause.Message, cause) { public long WindowId => id; }
    private readonly Dictionary<long, WindowSnapshot> originals = new();
    private readonly List<DesktopDividerWindow> dividers = new();
    private DropPreviewWindow? dropPreview;
    private readonly DispatcherTimer timer;
    private IReadOnlyList<DesktopMonitor> monitors = [];
    private WorkspaceState? preview;
    private (string Monitor, Guid? Target, Placement Placement, bool Section)? previewDestination;
    private readonly Dictionary<(string Monitor, Guid? Target, Placement Placement, bool Section), WorkspaceState?> dropProposals = new();
    private WindowNode? incoming;
    private long activeNativeDrag;
    private long lastActiveWindow;
    private readonly Dictionary<long, long> lastInteraction = new();
    private long nativeResizeWindow;
    private PixelRect? nativeStartBounds;
    private Divider? divider;
    private PixelPoint dividerStart;
    private string? dividerMonitor;
    private WorkspaceState? dragStart;
    private WindowSnapshot[]? liveResizeStart;
    private readonly Dictionary<long, PixelRect> liveBounds = new();
    private bool validPreview;
    public BentoSettings Settings { get; private set; } = BentoSettings.Load();
    public IReadOnlyList<AppWindow> Windows { get; private set; } = [];
    public bool Dragging => incoming is not null || divider is not null || nativeResizeWindow != 0;
    public WorkspaceState DisplayState => preview ?? history.Current;
    public string Status { get; private set; } = "";
    public bool Automatic => automatic;
    public int ManagedCount => history.Current.Windows.Count();

    public BentoController(Func<IReadOnlyList<AppWindow>>? windowSource = null, BentoSettings? settings = null, Func<long>? clock = null)
    {
        this.windowSource = windowSource;
        this.clock = clock ?? (() => Environment.TickCount64);
        if (settings is not null) Settings = settings;
        if (windowSource is null) snapLease = new SnapLease(Path.Combine(BentoSettings.DataDirectory, "snap-lease.txt"));
        source = new HwndSource(new HwndSourceParameters("Bento hotkeys") { Width = 0, Height = 0, WindowStyle = 0 });
        source.AddHook(WndProc);
        bool shortcut = !Settings.ShortcutEnabled || DesktopIntegration.RegisterShortcut(source.Handle, 1, Settings.Modifiers, Settings.Key);
        int shortcutError = DesktopIntegration.ShortcutError;
        events = new DesktopEvents();
        events.NativeDrag += OnNativeDrag;
        events.ForegroundChanged += () => Dispatch(() => { RememberActiveWindow(); PlaceDividersBelowInterface(); });
        trayInterface = new TrayInterface(this, RememberActiveWindow, () => lastActiveWindow);
        tray = trayInterface.Icon;
        timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        timer.Tick += (_, _) => Tick(); timer.Start();
        Microsoft.Win32.SystemEvents.UserPreferenceChanged += AppearanceChanged;
        if (!shortcut) Report($"Could not register {Settings.Shortcut} (Windows error {shortcutError}). Choose another shortcut in tray settings.");
        try { snapLease?.SetSuppressed(Settings.SuppressWindowsSnap); } catch (Exception ex) { Report(ex.Message); }
    }

    public void ShowInterface(string page = "Workspace")
    {
        if (disposed) return;
        if (appWindow is null) { appWindow = new BentoWindow(this); appWindow.Closed += (_, _) => appWindow = null; appWindow.Activated += (_, _) => PlaceDividersBelowInterface(); }
        appWindow.SelectPage(page); appWindow.Show(); appWindow.WindowState = WindowState.Normal; appWindow.Activate();
        PlaceDividersBelowInterface();
    }
    private void PlaceDividersBelowInterface()
    {
        if (disposed) return;
        var applications = Windows.Select(w => w.Id).ToList();
        if (appWindow?.IsVisible == true && appWindow.WindowState != WindowState.Minimized)
            applications.Add(new WindowInteropHelper(appWindow).Handle.ToInt64());
        foreach (var handle in dividers.Where(h => h.IsVisible))
            DesktopIntegration.PlaceBehindApplications(new WindowInteropHelper(handle).Handle, applications);
        RefreshBackdrops();
    }
    private void AppearanceChanged(object sender, Microsoft.Win32.UserPreferenceChangedEventArgs args) => Dispatch(() =>
    {
        AppTheme.Apply(Settings.Theme); WallpaperContrast.Invalidate();
        trayInterface.Refresh();
        foreach (var handle in dividers) handle.RefreshContrast();
    });
    public void SetAutomatic(bool enabled)
    {
        if (disposed) return;
        if (enabled == automatic) return;
        if (enabled) { ArrangeDesktop(); return; }
        Deactivate(restorePositions: savedSession is null);
    }
    public void ToggleBento() => SetAutomatic(!automatic);
    public void SaveBento()
    {
        if (disposed || !automatic || Dragging || !history.Current.Windows.Any()) return;
        savedSession = new(history.Current, SessionWindows);
        Report("Layout saved for this session. Turning Bento off will keep window positions.");
    }
    public void ClearSessionSave()
    {
        if (disposed) return;
        savedSession = null;
        Report("Session save cleared. Turning Bento off restores original positions.");
    }
    public void UseSessionSave()
    {
        if (disposed || Dragging || activeNativeDrag != 0 || savedSession is null) return;
        Windows = DiscoverWindows(useCache: false); monitors = WindowCatalog.Monitors();
        var next = savedSession.Reconcile(SessionWindows, monitors.Select(m => m.Id));
        if (!next.Windows.Any()) { Report("The saved windows are no longer available."); return; }
        if (!Commit(next)) return;
        automatic = true;
        released.UnionWith(Windows.Select(w => w.Id).Except(next.Windows.Select(w => w.WindowId)).Except(minimizedByBento.Keys));
        released.ExceptWith(next.Windows.Select(w => w.WindowId));
        snapLease?.SetSuppressed(Settings.SuppressWindowsSnap);
        RefreshDesktopDividers(); trayInterface.Refresh();
    }

    private void Dispatch(Action action)
    {
        if (disposed) return;
        Application.Current.Dispatcher.BeginInvoke(new Action(() => { if (!disposed) action(); }));
    }
    private nint WndProc(nint hwnd, int message, nint wparam, nint lparam, ref bool handled)
    {
        if (disposed) return 0;
        if (message == 0x312) { if (Settings.ShortcutEnabled) ToggleBento(); handled = true; }
        if (message is 0x7E or 0x2E0 or 0x1A)
            Dispatch(RefreshMonitorGeometry);
        return 0;
    }

    public void ArrangeDesktop()
    {
        if (disposed) return;
        if (activeNativeDrag != 0) return;
        CancelDrag();
        Windows = DiscoverWindows(useCache: false);
        RememberActiveWindow();
        var nextMonitors = WindowCatalog.Monitors();
        bool geometryChanged = !monitors.SequenceEqual(nextMonitors);
        monitors = nextMonitors;
        if (!automatic)
        {
            // Preserve originals retained by an explicit session save; never inherit
            // a disk layout or apply an old process snapshot to a reused HWND.
            foreach (long id in originals.Keys.Where(id => !Windows.Any(w => w.Id == id && w.ProcessId == originals[id].ProcessId)).ToArray()) originals.Remove(id);
            released.Clear(); failedMembership = null;
            WorkspaceState? resume = lastBento?.Reconcile(SessionWindows, monitors.Select(m => m.Id));
            if (resume is not null)
            {
                foreach (var leaf in resume.Windows.ToArray()) if (!Windows.Any(w => w.Id == leaf.WindowId)) resume = resume.Remove(leaf.WindowId);
                foreach (string id in resume.Roots.Keys.Where(id => !monitors.Any(m => m.Id == id)).ToArray()) resume = resume.WithRoot(id, null);
                if (Commit(resume)) geometryChanged = false;
            }
        }
        automatic = true;
        snapLease?.SetSuppressed(Settings.SuppressWindowsSnap);
        Synchronize(geometryChanged);
        RefreshBackdrops();
        RefreshDesktopDividers();
        trayInterface.Refresh();
    }
    private void CloseDesktopHelpers()
    {
        // Shutdown has already discarded gesture rollback snapshots.
        if (!disposed) CancelDrag();
        foreach (var handle in dividers.ToArray()) handle.Close();
        dividers.Clear();
        dropPreview?.Close(); dropPreview = null;
    }
    public void Refresh()
    {
        if (disposed) return;
        Windows = DiscoverWindows(useCache: false);
        if (automatic && !Dragging && activeNativeDrag == 0) Synchronize();
        PlaceDividersBelowInterface();
    }
    private IReadOnlyList<AppWindow> DiscoverWindows(bool useCache = true)
    {
        var visible = (windowSource?.Invoke() ?? WindowCatalog.Discover(includeMinimized: false,
            cache: useCache ? Windows.ToDictionary(w => w.Id) : null)).ToList();
        foreach (var (id, entry) in minimizedByBento.ToArray())
        {
            if (!WindowCatalog.Exists(id)) { minimizedByBento.Remove(id); continue; }
            if (visible.Any(w => w.Id == id) && !WindowCatalog.IsMinimized(id))
            { reopened.Add(id); minimizedByBento.Remove(id); }
            else if (WindowCatalog.IsMinimized(id) && !visible.Any(w => w.Id == id)) visible.Add(entry.Window);
        }
        return visible;
    }
    public void AutoArrangeAll()
    {
        if (disposed) return;
        if (activeNativeDrag != 0) return;
        CancelDrag(); released.Clear(); if (!automatic) originals.Clear(); automatic = true;
        snapLease?.SetSuppressed(Settings.SuppressWindowsSnap);
        Windows = DiscoverWindows(useCache: false); monitors = WindowCatalog.Monitors();
        Synchronize(rebuild: true);
        trayInterface.Refresh();
    }
    private void Synchronize(bool rebuild = false, HashSet<long>? excluded = null)
    {
        string membership = string.Join(";", Windows.Where(w => !released.Contains(w.Id)).OrderBy(w => w.Id)
            .Select(w => $"{w.Id}:{w.ProcessId}:{w.MonitorId}:{w.Minimum}")) + string.Join(";", monitors);
        if (!rebuild && reopened.Count == 0 && failedMembership == membership) return;
        try
        {
            var eligible = Windows.Where(w => !released.Contains(w.Id) && !(excluded?.Contains(w.Id) ?? false)).ToArray();
            var ids = eligible.Select(w => w.Id).ToHashSet();
            var state = history.Current;
            bool changed = rebuild;
            foreach (var leaf in state.Windows.ToArray())
                if (!ids.Contains(leaf.WindowId)) { state = state.Remove(leaf.WindowId); changed = true; }
            foreach (string id in state.Roots.Keys.Where(id => !monitors.Any(m => m.Id == id)).ToArray())
            { state = state.WithRoot(id, null); changed = true; }
            foreach (var monitor in monitors)
            {
                var assigned = eligible.Where(w => (string.IsNullOrEmpty(w.MonitorId) ? monitors.FirstOrDefault()?.Id : w.MonitorId) == monitor.Id).ToArray();
                var existing = state.Roots.GetValueOrDefault(monitor.Id);
                var group = assigned.OrderByDescending(w => lastInteraction.GetValueOrDefault(w.Id))
                    .Select(w => WindowNode.Create(w.Id, w.Minimum)).ToArray();
                var priority = reopened.Concat(group.Where(w => !history.Current.Windows.Any(old => old.WindowId == w.WindowId)
                    && !minimizedByBento.ContainsKey(w.WindowId)).Select(w => w.WindowId)).ToHashSet();
                var oldest = assigned.OrderBy(w => lastInteraction.GetValueOrDefault(w.Id)).Select(w => w.Id).ToArray();
                var root = AutoLayout.Fitting(group, Area(monitor), Settings.Gap, rebuild ? null : existing, priority, oldest);
                if (!Equals(root, existing)) changed = true;
                state = state.WithRoot(monitor.Id, root);
            }
            if (changed && !Commit(state))
            {
                excluded ??= new();
                if (rejectedWindow is long failed && excluded.Add(failed) && excluded.Count <= Windows.Count)
                { Synchronize(rebuild, excluded); return; }
                failedMembership = membership; return;
            }
            var included = state.Windows.Select(w => w.WindowId).ToHashSet();
            foreach (long id in included) minimizedByBento.Remove(id);
            if (Settings.MinimizeOverflow)
                foreach (var window in Windows.Where(w => !released.Contains(w.Id) && !included.Contains(w.Id) && !minimizedByBento.ContainsKey(w.Id)))
                {
                    if (WindowCatalog.IsMinimized(window.Id)) continue;
                    try
                    {
                        var snapshot = native.Capture(window.Id);
                        native.Minimize(window.Id);
                        if (WindowCatalog.IsMinimized(window.Id)) minimizedByBento[window.Id] = (window, snapshot);
                    }
                    catch { /* Unsupported apps stay visible without blocking the rest. */ }
                }
            failedMembership = excluded?.Count > 0 ? membership : null;
            reopened.Clear();
        }
        catch (Exception ex) { failedMembership = membership; Report(ex.Message); }
    }
    public PixelRect Area(DesktopMonitor monitor) => monitor.WorkArea.Inset(Settings.Margin);
    public LayoutResult Layout(DesktopMonitor monitor, WorkspaceState? state = null)
    {
        (state ?? DisplayState).Roots.TryGetValue(monitor.Id, out var root);
        return LayoutEngine.Calculate(root, Area(monitor), Settings.Gap);
    }
    public void BeginDrag(long id)
    {
        if (disposed) return;
        var window = Windows.FirstOrDefault(w => w.Id == id);
        if (window is null) return;
        CancelDrag(); lastActiveWindow = id;
        transition?.Dispose();
        incoming = history.Current.Windows.FirstOrDefault(w => w.WindowId == id) ?? WindowNode.Create(id, window.Minimum);
        timer.Interval = TimeSpan.FromMilliseconds(16);
        foreach (var handle in dividers) handle.Hide();
        UpdatePreview();
    }
    public void BeginDivider(DesktopMonitor monitor, Divider value, PixelPoint? touch = null)
    {
        if (disposed) return;
        CancelDrag();
        dividerSurface = value.SplitId;
        var point = touch ?? WindowCatalog.Cursor;
        var handles = Handles(monitor, history.Current);
        var selected = ResizeHandles.Hit(handles, point, monitor.Scale);
        divider = selected?.Divider ?? value; dividerMonitor = monitor.Id;
        dragStart = selected is null ? history.Current : history.Current.WithRoot(monitor.Id, selected.Root);
        transition?.Dispose(); transition = null;
        liveResizeStart = Layout(monitor, dragStart).Regions.Select(r => native.Capture(r.Window.WindowId)).ToArray();
        foreach (var region in Layout(monitor, dragStart).Regions) liveBounds[region.Window.WindowId] = native.VisibleBounds(region.Window.WindowId);
        touchPoint = touch; dividerStart = touch ?? WindowCatalog.Cursor;
        timer.Interval = TimeSpan.FromMilliseconds(16);
        foreach (var handle in dividers) if (handle.SplitId != dividerSurface) handle.Hide();
        UpdatePreview(touch);
    }
    public void BeginNativeResize(long id)
    {
        if (disposed) return;
        CancelDrag();
        if (!history.Current.Windows.Any(w => w.WindowId == id)) return;
        nativeResizeWindow = id; dragStart = history.Current;
        timer.Interval = TimeSpan.FromMilliseconds(16);
        foreach (var handle in dividers) handle.Hide();
    }
    public void PreviewDrag(PixelPoint point) { if (touchPoint.HasValue) touchPoint = point; UpdatePreview(point); }
    private void Tick()
    {
        if (disposed) return;
        if (Dragging)
        {
            long id = incoming?.WindowId ?? nativeResizeWindow;
            if (id != 0 && !WindowCatalog.Exists(id))
            { activeNativeDrag = 0; nativeStartBounds = null; CancelDrag(); }
            else { UpdatePreview(); return; }
        }
        if (activeNativeDrag != 0 && !WindowCatalog.Exists(activeNativeDrag))
        { activeNativeDrag = 0; nativeStartBounds = null; CancelDrag(); }
        if (!automatic || activeNativeDrag != 0) return;
        RememberActiveWindow();
        RefreshMonitorGeometry();
        Windows = DiscoverWindows();
        Synchronize();
        PlaceDividersBelowInterface();
    }
    private void RefreshMonitorGeometry()
    {
        if (disposed) return;
        var latest = WindowCatalog.Monitors();
        if (monitors.SequenceEqual(latest) || activeNativeDrag != 0 || Dragging) return;
        foreach (var monitor in monitors)
            if (history.Current.Roots.GetValueOrDefault(monitor.Id) is { } root && !workAreaBaseline.ContainsKey(monitor.Id))
                workAreaBaseline[monitor.Id] = (root, Area(monitor));
        monitors = latest;
        foreach (var id in workAreaBaseline.Keys.Where(id => !latest.Any(m => m.Id == id)).ToArray()) workAreaBaseline.Remove(id);
        if (!automatic) return;
        Windows = DiscoverWindows(useCache: false);
        reflowing = true;
        try
        {
            var state = history.Current;
            foreach (var monitor in monitors)
                if (state.Roots.GetValueOrDefault(monitor.Id) is { } root && workAreaBaseline.TryGetValue(monitor.Id, out var reference))
                    state = state.WithRoot(monitor.Id, LayoutReflow.PreservingSeams(root, reference.Root, reference.Area, Area(monitor), Settings.Gap));
            if (Commit(state)) Synchronize();
        }
        catch (LayoutConstraintException) { Synchronize(rebuild: true); }
        finally { reflowing = false; }
    }
    private void OnNativeDrag(long id, bool starting) => Dispatch(() =>
    {
        if (starting)
        {
            if (!automatic) return;
            try
            {
                // Reuse known minimum sizes: querying every application synchronously here delays the native drag.
                Windows = DiscoverWindows();
                activeNativeDrag = id; nativeStartBounds = null;
                if (!Windows.Any(w => w.Id == id))
                {
                    // Settings and floating/excluded windows still suppress grip
                    // input while their native title bar or border is held.
                    foreach (var handle in dividers) handle.Hide();
                    return;
                }
                nativeStartBounds = native.VisibleBounds(id);
                if (native.IsResizeInteraction(id, WindowCatalog.Cursor)) BeginNativeResize(id);
                else BeginDrag(id);
            }
            catch (Exception ex)
            { activeNativeDrag = 0; nativeStartBounds = null; CancelDrag(); Report(ex.Message); }
            return;
        }
        if (activeNativeDrag != id) return;
        activeNativeDrag = 0;
        try
        {
            // Native Escape and a click without movement both return the window to its starting bounds.
            if (Dragging && WindowCatalog.Exists(id) && nativeStartBounds is { } start)
            {
                var end = native.VisibleBounds(id);
                bool changed = Math.Abs(end.X - start.X) > 2 || Math.Abs(end.Y - start.Y) > 2 ||
                    Math.Abs(end.Width - start.Width) > 2 || Math.Abs(end.Height - start.Height) > 2;
                if (changed) FinishDrag(); else CancelDrag();
            }
            else CancelDrag();
        }
        catch (Exception ex) { CancelDrag(); Report(ex.Message); }
        finally { nativeStartBounds = null; }
    });
    private void UpdatePreview(PixelPoint? position = null)
    {
        if (disposed) return;
        var point = position ?? touchPoint ?? WindowCatalog.Cursor;
        previewDestination = null;
        preview = null; validPreview = false;
        try
        {
            if (nativeResizeWindow != 0)
            {
                var sourceMonitor = monitors.FirstOrDefault(m => LayoutEngine.Windows(dragStart!.Roots.GetValueOrDefault(m.Id))
                    .Any(w => w.WindowId == nativeResizeWindow));
                if (sourceMonitor is null || !WindowCatalog.Exists(nativeResizeWindow)) { dropPreview?.Hide(); return; }
                var root = dragStart!.Roots[sourceMonitor.Id]!;
                preview = dragStart.WithRoot(sourceMonitor.Id, LayoutEngine.ResizeWindow(root, nativeResizeWindow,
                    native.VisibleBounds(nativeResizeWindow), Area(sourceMonitor), Settings.Gap));
            }
            else if (divider is not null && dividerMonitor is not null)
            {
                var root = dragStart!.Roots[dividerMonitor]!;
                var candidate = LayoutEngine.ResizeDivider(root, divider, point, dividerStart, Settings.Gap);
                var monitor = monitors.Single(m => m.Id == dividerMonitor);
                preview = dragStart.WithRoot(dividerMonitor, ReferenceEquals(candidate, root) ? root : LayoutInteraction.SnapSeam(candidate, divider.SplitId,
                    Area(monitor), Settings.Gap, (int)Math.Round(12 * monitor.Scale)));
            }
            else if (incoming is not null)
            {
                var monitor = monitors.FirstOrDefault(m => m.Bounds.Contains(point));
                if (monitor is null) { dragIntent.Reset(); dropPreview?.Hide(); return; }
                var sourceRoot = history.Current.Roots.GetValueOrDefault(monitor.Id);
                var edge = LayoutInteraction.ScreenEdge(monitor.Bounds, point, (int)Math.Round(20 * monitor.Scale));
                if (edge is { } sectionEdge && sourceRoot is not null && LayoutEngine.Windows(sourceRoot).Any(w => w.WindowId == incoming.WindowId))
                {
                    dragIntent.Reset(); intent = new(sectionEdge, 0, false);
                    previewDestination = (monitor.Id, null, sectionEdge, true);
                    if (!dropProposals.TryGetValue(previewDestination.Value, out var section))
                    {
                        var moved = LayoutInteraction.MoveSection(sourceRoot, incoming.WindowId, sectionEdge, Area(monitor), Settings.Gap);
                        section = moved is null ? null : history.Current.WithRoot(monitor.Id, moved);
                        dropProposals[previewDestination.Value] = section;
                    }
                    if (section is null) { dropPreview?.Hide(); return; }
                    preview = section; validPreview = true; PresentDropPreview(); return;
                }
                if (!Area(monitor).Contains(point)) { dragIntent.Reset(); dropPreview?.Hide(); return; }
                var target = Layout(monitor, history.Current).Regions.FirstOrDefault(r => r.Bounds.Contains(point));
                if (target?.Window.WindowId == incoming.WindowId) { dragIntent.Reset(); dropPreview?.Hide(); return; }
                // Gaps are deliberately non-droppable, so divider gestures cannot silently insert windows.
                if (target is null && history.Current.Roots.GetValueOrDefault(monitor.Id) is not null) { dragIntent.Reset(); dropPreview?.Hide(); return; }
                var bounds = target?.Bounds ?? Area(monitor);
                dropTargetBounds = bounds;
                intent = target is null ? new(Placement.Center, 0, false) :
                    dragIntent.Update(monitor.Id, target.Window.Id, bounds, point, clock(), Settings.SplitHoldMs, monitor.Scale);
                var placement = intent.Placement;
                if (placement == Placement.Center && target is not null && !history.Current.Windows.Any(w => w.WindowId == incoming.WindowId))
                    placement = bounds.Width >= bounds.Height ? Placement.Right : Placement.Bottom;
                var destinationKey = (monitor.Id, target?.Window.Id, placement, false);
                previewDestination = destinationKey;
                if (dropProposals.TryGetValue(destinationKey, out var cached))
                {
                    if (cached is null) throw new LayoutConstraintException("This destination cannot fit these windows.");
                    preview = cached; validPreview = true; PresentDropPreview(); return;
                }
                preview = history.Current.Place(monitor.Id, target?.Window.Id, incoming, placement);
                // Also scale the displaced window's constraint when swapping between different DPI monitors.
                foreach (var destination in monitors)
                {
                    var root = preview.Roots.GetValueOrDefault(destination.Id);
                    foreach (var window in LayoutEngine.Windows(root).ToArray())
                    {
                        double scale = destination.Scale / WindowCatalog.WindowScale(window.WindowId);
                        if (Math.Abs(scale - 1) < .001) continue;
                        root = LayoutEngine.Replace(root!, window.Id, window with { Minimum = new PixelSize(
                            (int)Math.Ceiling(window.Minimum.Width * scale), (int)Math.Ceiling(window.Minimum.Height * scale)) });
                    }
                    preview = preview.WithRoot(destination.Id, root);
                }
                previewDestination = destinationKey;
            }
            if (preview is null) return;
            Validate(preview); validPreview = true;
            if (incoming is not null && previewDestination is { } key) dropProposals[key] = preview;
            if (divider is not null && dividerMonitor is not null)
            {
                var monitor = monitors.Single(m => m.Id == dividerMonitor);
                foreach (var region in Layout(monitor, preview).Regions)
                {
                    if (liveBounds.GetValueOrDefault(region.Window.WindowId) == region.Bounds) continue;
                    native.Move(region.Window.WindowId, region.Bounds);
                    liveBounds[region.Window.WindowId] = region.Bounds;
                }
            }
            PresentDropPreview();
        }
        catch (Exception ex) when (ex is LayoutConstraintException or InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            if (liveResizeStart is not null) CancelDrag();
            if (incoming is not null && previewDestination is { } key) dropProposals[key] = null;
            preview = null; previewDestination = null; validPreview = false;
            var monitor = monitors.FirstOrDefault(m => Area(m).Contains(point));
            if (incoming is not null && monitor is not null)
                (dropPreview ??= new DropPreviewWindow()).Present(dropTargetBounds, monitor.Scale, false, Placement.Center, 0, conflict: true, dimBounds: monitor.Bounds);
            else dropPreview?.Hide();
            Status = ex.Message;
        }
    }
    public void FinishDrag(PixelPoint? position = null)
    {
        if (disposed) return;
        UpdatePreview(position);
        var next = validPreview ? preview : null;
        bool nativeGesture = nativeStartBounds.HasValue;
        var liveStart = liveResizeStart;
        ClearDrag(restoreLive: false);
        bool applied = next is not null && Commit(next, animate: liveStart is null);
        if (!applied && liveStart is not null) RestoreLiveResize(liveStart);
        if (!applied && nativeGesture)
        {
            try { Apply(history.Current, history.Current); RefreshDesktopDividers(); }
            catch (Exception ex) { Report(ex.Message); }
        }
        if (!applied) RefreshDesktopDividers();
    }
    public void CancelDrag() { if (!disposed) ClearDrag(restoreLive: true); }
    private void RestoreLiveResize(WindowSnapshot[] snapshots)
    {
        foreach (var snapshot in snapshots)
            try { native.Restore(snapshot); } catch (Exception ex) { Status = ex.Message; }
    }
    private void ClearDrag(bool restoreLive)
    {
        var snapshots = liveResizeStart; liveResizeStart = null; liveBounds.Clear();
        if (restoreLive && snapshots is not null) RestoreLiveResize(snapshots);
        incoming = null; divider = null; dividerSurface = null; dividerMonitor = null; dragStart = null; preview = null;
        previewDestination = null; dropProposals.Clear();
        dragIntent.Reset(); intent = default; touchPoint = null;
        nativeResizeWindow = 0; validPreview = false;
        timer.Interval = TimeSpan.FromSeconds(1);
        dropPreview?.Hide();
        if (restoreLive)
            foreach (var handle in dividers) { handle.ResetPresentation(); handle.Show(); }
        PlaceDividersBelowInterface();
    }
    public void Remove(long id)
    {
        if (disposed) return;
        if (!history.Current.Windows.Any(w => w.WindowId == id)) return;
        CancelDrag(); if (Commit(history.Current.Remove(id))) released.Add(id);
    }
    private void RememberActiveWindow()
    {
        long id = WindowCatalog.Foreground;
        if (Windows.Any(w => w.Id == id)) { lastActiveWindow = id; lastInteraction[id] = clock(); }
        foreach (var missing in lastInteraction.Keys.Where(id => !Windows.Any(w => w.Id == id)).ToArray()) lastInteraction.Remove(missing);
    }
    private void Validate(WorkspaceState state) { foreach (var monitor in monitors) Layout(monitor, state); }
    private bool Commit(WorkspaceState state, bool restoreRemoved = true, bool animate = true)
    {
        rejectedWindow = null;
        try
        {
            Validate(state); Apply(history.Current, state, restoreRemoved, animate); history.Commit(state); failedMembership = null;
            if (!reflowing) workAreaBaseline.Clear();
            Status = "Windows arranged on the desktop.";
            RefreshDesktopDividers(); return true;
        }
        catch (Exception ex) { rejectedWindow = (ex as PlacementFailure)?.WindowId; if (rejectedWindow is null) Report(ex.Message); return false; }
    }
    private void Apply(WorkspaceState previous, WorkspaceState next, bool restoreRemoved = true, bool animate = true)
    {
        var ids = previous.Windows.Concat(next.Windows).Select(w => w.WindowId).Distinct().Where(WindowCatalog.Exists).ToArray();
        var rollback = ids.Select(native.Capture).ToArray();
        foreach (var snapshot in rollback)
            if (originals.TryGetValue(snapshot.WindowId, out var known) && known.ProcessId != snapshot.ProcessId)
                throw new InvalidOperationException("An application has restarted. Restart Bento to manage it again.");
        try
        {
            foreach (var id in next.Windows.Select(w => w.WindowId))
                if (!originals.ContainsKey(id)) originals[id] = minimizedByBento.TryGetValue(id, out var minimized) ? minimized.Snapshot : native.Capture(id);
            var nextIds = next.Windows.Select(w => w.WindowId).ToHashSet();
            var removed = previous.Windows.Where(w => restoreRemoved && !nextIds.Contains(w.WindowId) && Windows.Any(current => current.Id == w.WindowId))
                .Where(w => originals.ContainsKey(w.WindowId)).Select(w => originals[w.WindowId]).ToArray();
            var regions = monitors.SelectMany(m => Layout(m, next).Regions).ToArray();
            transition?.Dispose(); transition = null;
            if (animate && Settings.Animate && SystemParameters.ClientAreaAnimation && regions.Length + removed.Length <= 16)
            {
                try
                {
                    var moves = regions.Select(r => (r.Window.WindowId, native.VisibleBounds(r.Window.WindowId), r.Bounds))
                        .Concat(removed.Select(s => (s.WindowId, native.VisibleBounds(s.WindowId), s.VisibleBounds)));
                    transition = new DesktopTransition(moves, Settings.AnimationMs);
                }
                catch { transition = null; }
            }
            foreach (var original in removed) native.Restore(original);
            foreach (var region in regions)
                if (WindowCatalog.IsMinimized(region.Window.WindowId) || native.VisibleBounds(region.Window.WindowId) != region.Bounds)
                {
                    try { native.Move(region.Window.WindowId, region.Bounds); }
                    catch (Exception ex) { throw new PlacementFailure(region.Window.WindowId, ex); }
                }
            transition?.Play();

        }
        catch
        {
            transition?.Dispose(); transition = null;
            foreach (var snapshot in rollback) { try { native.Restore(snapshot); } catch { /* Best effort if a process exits or denies access. */ } }
            throw;
        }
    }
    public void Undo() => NavigateHistory(false);
    public void Redo() => NavigateHistory(true);
    private void NavigateHistory(bool redo)
    {
        if (!automatic) return;
        CancelDrag(); monitors = WindowCatalog.Monitors();
        var before = history.Current;
        var next = redo ? history.Redo() : history.Undo();
        if (ReferenceEquals(before, next)) return;
        try
        {
            foreach (var window in next.Windows.ToArray()) if (!WindowCatalog.Exists(window.WindowId)) next = next.Remove(window.WindowId);
            foreach (string id in next.Roots.Keys.Where(id => !monitors.Any(m => m.Id == id)).ToArray()) next = next.WithRoot(id, null);
            Validate(next); Apply(before, next);
            if (!ReferenceEquals(next, history.Current)) history.Commit(next);
            var nextIds = next.Windows.Select(w => w.WindowId).ToHashSet();
            released.ExceptWith(nextIds);
            released.UnionWith(before.Windows.Select(w => w.WindowId).Where(id => !nextIds.Contains(id)));
            RefreshDesktopDividers();
        }
        catch (Exception ex) { if (redo) history.Undo(); else history.Redo(); Report(ex.Message); }
    }
    public void RestoreAll() => Deactivate(restorePositions: true);
    private void Deactivate(bool restorePositions)
    {
        if (disposed) return;
        CancelDrag();
        var previous = history.Current;
        if (Commit(new WorkspaceState(), restoreRemoved: restorePositions))
        {
            if (previous.Windows.Any()) lastBento = new(previous, SessionWindows);
            if (restorePositions)
                foreach (var entry in originals.Where(e => !previous.Windows.Any(w => w.WindowId == e.Key)).ToArray())
                    try { native.Restore(entry.Value); } catch (Exception ex) { Report(ex.Message); }
            foreach (var (id, entry) in minimizedByBento.ToArray())
            {
                try { native.Restore(entry.Snapshot); minimizedByBento.Remove(id); }
                catch (Exception ex) { Report(ex.Message); }
            }
            automatic = false; released.Clear(); reopened.Clear();
            snapLease?.SetSuppressed(false);
            Status = restorePositions ? "Windows restored · activate Bento again to resume" : "Bento off · session layout kept in place";
            RefreshDesktopDividers();
            if (restorePositions) originals.Clear();
            trayInterface.Refresh();
        }
    }
    internal bool SaveSettingsOnShutdown(BentoSettings settings)
    {
        if (!disposed || !settings.IsValid) return false;
        try { settings.Save(); Settings = settings; return true; }
        catch (Exception ex) { Status = ex.Message; return false; }
    }
    public bool UpdateSettings(BentoSettings settings)
    {
        if (disposed) return false;
        if (!settings.IsValid) { Report("Please check the settings values."); return false; }
        if (Dragging || activeNativeDrag != 0) { Report("Finish dragging before changing settings."); return false; }
        var old = Settings;
        workAreaBaseline.Clear();
        bool changed = settings.ShortcutEnabled != old.ShortcutEnabled || settings.Key != old.Key || settings.Modifiers != old.Modifiers;
        if (changed)
        {
            DesktopIntegration.UnregisterShortcut(source.Handle, 1);
            if (settings.ShortcutEnabled && !DesktopIntegration.RegisterShortcut(source.Handle, 1, settings.Modifiers, settings.Key))
            {
                if (old.ShortcutEnabled) DesktopIntegration.RegisterShortcut(source.Handle, 1, old.Modifiers, old.Key);
                Report("That shortcut is in use. Try another combination."); return false;
            }
        }
        Settings = settings;
        try
        {
            Validate(history.Current); Apply(history.Current, history.Current);
            snapLease?.SetSuppressed(automatic && settings.SuppressWindowsSnap);
            settings.Save(); AppTheme.Apply(settings.Theme); RefreshDesktopDividers(); return true;
        }
        catch (Exception ex)
        {
            Settings = old;
            try { snapLease?.SetSuppressed(automatic && old.SuppressWindowsSnap); } catch { }
            try { Apply(history.Current, history.Current); } catch { /* Preserve the original failure report. */ }
            if (changed) { DesktopIntegration.UnregisterShortcut(source.Handle, 1); if (old.ShortcutEnabled) DesktopIntegration.RegisterShortcut(source.Handle, 1, old.Modifiers, old.Key); }
            Report(ex.Message); return false;
        }
    }
    public void Report(string text)
    {
        Status = text;
        if (!disposed) tray?.ShowBalloonTip(4000, "Bento", text, Forms.ToolTipIcon.Info);
    }
    private void PresentDropPreview()
    {
        if (preview is null || nativeResizeWindow != 0) { dropPreview?.Hide(); return; }
        if (divider is not null && dividerMonitor is not null)
        {
            dropPreview?.Hide();
            var monitor = monitors.Single(m => m.Id == dividerMonitor);
            var boundary = Layout(monitor, preview).Dividers.Single(d => d.SplitId == divider.SplitId);
            dividers.FirstOrDefault(h => h.SplitId == dividerSurface)?.PresentResize(boundary.Bounds);
            return;
        }
        foreach (var monitor in monitors)
        {
            var layout = Layout(monitor, preview);
            PixelRect? bounds = incoming is not null
                ? previewDestination?.Monitor == monitor.Id ? layout.Regions.FirstOrDefault(r => r.Window.WindowId == incoming.WindowId)?.Bounds : null
                : layout.Dividers.FirstOrDefault(d => d.SplitId == divider?.SplitId)?.Bounds;
            if (bounds is null) continue;
            (dropPreview ??= new DropPreviewWindow()).Present(bounds.Value, monitor.Scale,
                Settings.Animate && SystemParameters.ClientAreaAnimation, previewDestination?.Placement ?? Placement.Center, intent.Progress, dimBounds: monitor.Bounds);
            return;
        }
        dropPreview?.Hide();
    }
    private IReadOnlyList<ResizeHandle> Handles(DesktopMonitor monitor, WorkspaceState state) =>
        state.Roots.GetValueOrDefault(monitor.Id) is { } root ? resizeHandles.Get(monitor.Id, root, Area(monitor), Settings.Gap) : [];
    private void RefreshDesktopDividers()
    {
        if (disposed || Dragging) return;
        RefreshBackdrops();
        try
        {
            resizeHandles.Retain(monitors.Select(m => m.Id).ToHashSet());
            var wanted = automatic ? monitors.SelectMany(m =>
            {
                var handles = Handles(m, history.Current);
                return handles.Where(h => ResizeHandles.IsUniversal(h, handles)).Select(h => (Monitor: m, Handle: h, All: handles));
            }).ToArray() : [];
            foreach (var handle in dividers.Where(h => !wanted.Any(w => w.Handle.Divider.SplitId == h.SplitId && w.Monitor.Id == h.MonitorId && w.Monitor.Scale == h.MonitorScale)).ToArray())
            { handle.Close(); dividers.Remove(handle); }
            foreach (var (monitor, geometry, all) in wanted)
            {
                var boundary = geometry.Divider;
                var handle = dividers.FirstOrDefault(h => h.SplitId == boundary.SplitId && h.MonitorId == monitor.Id);
                if (handle is null) { handle = new DesktopDividerWindow(this, monitor, boundary); dividers.Add(handle); handle.Show(); }
                else { handle.UpdateDivider(boundary); if (!handle.IsVisible) handle.Show(); }
                handle.UpdateHandle(geometry, all);
            }
            PlaceDividersBelowInterface();
        }
        catch (LayoutConstraintException) { /* Geometry may no longer fit after a display change. */ }
    }
    private void CloseBackdrops()
    {
        foreach (var backdrop in backdrops.Values) backdrop.Close();
        backdrops.Clear();
    }
    private void RefreshBackdrops()
    {
        if (disposed) return;
        var occupied = automatic ? monitors.Where(m => history.Current.Roots.GetValueOrDefault(m.Id) is not null).ToArray() : [];
        foreach (string id in backdrops.Keys.Where(id => !occupied.Any(m => m.Id == id)).ToArray())
        { backdrops[id].Close(); backdrops.Remove(id); }
        var applications = Windows.Select(w => w.Id).ToList();
        if (appWindow?.IsVisible == true && appWindow.WindowState != WindowState.Minimized) applications.Add(new WindowInteropHelper(appWindow).Handle.ToInt64());
        applications.AddRange(dividers.Where(w => w.IsVisible).Select(w => new WindowInteropHelper(w).Handle.ToInt64()));
        foreach (var monitor in occupied)
        {
            if (!backdrops.TryGetValue(monitor.Id, out var backdrop)) backdrops[monitor.Id] = backdrop = new();
            backdrop.Present(monitor, Settings.BackgroundDarkness, applications);
        }
    }
    public void Dispose()
    {
        if (disposed) return;
        // Quit and update end this session without restoring native windows.
        // Invalidate queued work before closing helpers: capture loss and settings
        // close handlers can otherwise roll back a live resize or apply settings.
        disposed = true;
        automatic = false;
        timer.Stop();
        appWindow?.FlushSettingsForShutdown();
        ClearDrag(restoreLive: false);
        activeNativeDrag = 0; nativeStartBounds = null;
        resizeHandles.Clear(); workAreaBaseline.Clear(); savedSession = null; lastBento = null;
        Microsoft.Win32.SystemEvents.UserPreferenceChanged -= AppearanceChanged;
        WallpaperContrast.Invalidate();
        events.Dispose(); transition?.Dispose(); CloseDesktopHelpers(); appWindow?.Close();
        CloseBackdrops();
        try { snapLease?.Dispose(); } catch { /* The recovery journal is kept for the next launch. */ }
        DesktopIntegration.UnregisterShortcut(source.Handle, 1); source.Dispose(); trayInterface.Dispose();
    }
}
