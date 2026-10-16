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
    private WorkspaceState? lastBento;
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
    private (string Monitor, Guid? Target, Placement Placement)? previewDestination;
    private WindowNode? incoming;
    private long activeNativeDrag;
    private long lastActiveWindow;
    private long nativeResizeWindow;
    private PixelRect? nativeStartBounds;
    private Divider? divider;
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
        events.ForegroundChanged += () => Dispatch(PlaceDividersBelowInterface);
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
        if (enabled == automatic) return;
        if (enabled) { ArrangeDesktop(); return; }
        RestoreAll();
    }
    public void ToggleBento() => SetAutomatic(!automatic);
    public void SaveBento()
    {
        if (!automatic || Dragging || !history.Current.Windows.Any()) return;
        try { SavedBentoLayout.Capture(history.Current, Windows).Save(); Report("Bento layout saved."); }
        catch (Exception ex) { Report(ex.Message); }
    }

    private static void Dispatch(Action action) => Application.Current.Dispatcher.BeginInvoke(action);
    private nint WndProc(nint hwnd, int message, nint wparam, nint lparam, ref bool handled)
    {
        if (message == 0x312) { if (Settings.ShortcutEnabled) ToggleBento(); handled = true; }
        if (message is 0x7E or 0x2E0 or 0x1A)
            Dispatch(RefreshMonitorGeometry);
        return 0;
    }

    public void ArrangeDesktop()
    {
        if (activeNativeDrag != 0) return;
        CancelDrag();
        Windows = DiscoverWindows(useCache: false);
        RememberActiveWindow();
        var nextMonitors = WindowCatalog.Monitors();
        bool geometryChanged = !monitors.SequenceEqual(nextMonitors);
        monitors = nextMonitors;
        if (!automatic)
        {
            originals.Clear(); released.Clear(); failedMembership = null;
            WorkspaceState? resume = lastBento;
            if (resume is null && windowSource is null)
                try { resume = SavedBentoLayout.Load()?.Restore(Windows, monitors.Select(m => m.Id)); }
                catch (Exception ex) { Report(ex.Message); }
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
        CancelDrag();
        foreach (var handle in dividers.ToArray()) handle.Close();
        dividers.Clear();
        dropPreview?.Close(); dropPreview = null;
    }
    public void Refresh()
    {
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
                var group = assigned.Select(w => WindowNode.Create(w.Id, w.Minimum)).ToArray();
                var root = AutoLayout.Fitting(group, Area(monitor), Settings.Gap, rebuild ? null : existing, reopened);
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
        CancelDrag(); divider = value; dividerMonitor = monitor.Id; dragStart = history.Current;
        transition?.Dispose(); transition = null;
        liveResizeStart = Layout(monitor, dragStart).Regions.Select(r => native.Capture(r.Window.WindowId)).ToArray();
        foreach (var region in Layout(monitor, dragStart).Regions) liveBounds[region.Window.WindowId] = native.VisibleBounds(region.Window.WindowId);
        touchPoint = touch;
        timer.Interval = TimeSpan.FromMilliseconds(16);
        foreach (var handle in dividers) if (handle.SplitId != value.SplitId) handle.Hide();
        UpdatePreview(touch);
    }
    public void BeginNativeResize(long id)
    {
        CancelDrag();
        if (!history.Current.Windows.Any(w => w.WindowId == id)) return;
        nativeResizeWindow = id; dragStart = history.Current;
        timer.Interval = TimeSpan.FromMilliseconds(16);
        foreach (var handle in dividers) handle.Hide();
    }
    public void PreviewDrag(PixelPoint point) { if (touchPoint.HasValue) touchPoint = point; UpdatePreview(point); }
    private void Tick()
    {
        if (Dragging)
        {
            long id = incoming?.WindowId ?? nativeResizeWindow;
            if (id != 0 && !WindowCatalog.Exists(id))
            { activeNativeDrag = 0; nativeStartBounds = null; CancelDrag(); }
            else { UpdatePreview(); return; }
        }
        if (!automatic || activeNativeDrag != 0) return;
        RememberActiveWindow();
        RefreshMonitorGeometry();
        Windows = DiscoverWindows();
        Synchronize();
        PlaceDividersBelowInterface();
    }
    private void RefreshMonitorGeometry()
    {
        var latest = WindowCatalog.Monitors();
        if (monitors.SequenceEqual(latest) || activeNativeDrag != 0 || Dragging) return;
        monitors = latest;
        if (automatic) { Windows = DiscoverWindows(useCache: false); Synchronize(rebuild: true); }
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
                if (!Windows.Any(w => w.Id == id)) return;
                activeNativeDrag = id;
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
        var point = position ?? touchPoint ?? WindowCatalog.Cursor;
        var previousPreview = preview;
        var previousDestination = previewDestination;
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
                var rect = divider.ParentBounds;
                bool horizontal = divider.Axis == SplitAxis.Horizontal;
                double ratio = ((horizontal ? point.X - rect.X : point.Y - rect.Y) - Settings.Gap / 2d) /
                    Math.Max(1, (horizontal ? rect.Width : rect.Height) - Settings.Gap);
                var root = dragStart!.Roots[dividerMonitor]!;
                preview = dragStart.WithRoot(dividerMonitor, LayoutEngine.Resize(root, divider.SplitId, ratio));
            }
            else if (incoming is not null)
            {
                var monitor = monitors.FirstOrDefault(m => Area(m).Contains(point));
                if (monitor is null) { dragIntent.Reset(); dropPreview?.Hide(); return; }
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
                var destinationKey = (monitor.Id, target?.Window.Id, placement);
                if (previousPreview is not null && previousDestination == destinationKey)
                {
                    preview = previousPreview; previewDestination = destinationKey; validPreview = true;
                    PresentDropPreview(); return;
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
            preview = null; previewDestination = null; validPreview = false;
            var monitor = monitors.FirstOrDefault(m => Area(m).Contains(point));
            if (incoming is not null && monitor is not null)
                (dropPreview ??= new DropPreviewWindow()).Present(dropTargetBounds, monitor.Scale, false, Placement.Center, 0, conflict: true);
            else dropPreview?.Hide();
            Status = ex.Message;
        }
    }
    public void FinishDrag(PixelPoint? position = null)
    {
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
    }
    public void CancelDrag() => ClearDrag(restoreLive: true);
    private void RestoreLiveResize(WindowSnapshot[] snapshots)
    {
        foreach (var snapshot in snapshots)
            try { native.Restore(snapshot); } catch (Exception ex) { Status = ex.Message; }
    }
    private void ClearDrag(bool restoreLive)
    {
        var snapshots = liveResizeStart; liveResizeStart = null; liveBounds.Clear();
        if (restoreLive && snapshots is not null) RestoreLiveResize(snapshots);
        incoming = null; divider = null; dividerMonitor = null; dragStart = null; preview = null;
        previewDestination = null;
        dragIntent.Reset(); intent = default; touchPoint = null;
        nativeResizeWindow = 0; validPreview = false;
        timer.Interval = TimeSpan.FromSeconds(1);
        dropPreview?.Hide();
        foreach (var handle in dividers) { handle.ResetPresentation(); handle.Show(); }
        PlaceDividersBelowInterface();
    }
    public void Remove(long id)
    {
        if (!history.Current.Windows.Any(w => w.WindowId == id)) return;
        CancelDrag(); if (Commit(history.Current.Remove(id))) released.Add(id);
    }
    private void RememberActiveWindow()
    {
        long id = WindowCatalog.Foreground;
        if (Windows.Any(w => w.Id == id)) lastActiveWindow = id;
    }
    private void Validate(WorkspaceState state) { foreach (var monitor in monitors) Layout(monitor, state); }
    private bool Commit(WorkspaceState state, bool restoreRemoved = true, bool animate = true)
    {
        rejectedWindow = null;
        try
        {
            Validate(state); Apply(history.Current, state, restoreRemoved, animate); history.Commit(state); failedMembership = null;
            if (windowSource is null && state.Windows.Any())
                try { SavedBentoLayout.Capture(state, Windows).Save(); } catch (Exception ex) { Report($"Layout arranged, but could not save it: {ex.Message}"); }
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
    public void RestoreAll()
    {
        CancelDrag();
        var previous = history.Current;
        if (Commit(new WorkspaceState()))
        {
            if (previous.Windows.Any()) lastBento = previous;
            foreach (var (id, entry) in minimizedByBento.ToArray())
            {
                try { native.Restore(entry.Snapshot); minimizedByBento.Remove(id); }
                catch (Exception ex) { Report(ex.Message); }
            }
            automatic = false; released.Clear(); reopened.Clear();
            snapLease?.SetSuppressed(false);
            Status = "Windows restored · automatic arrangement paused · activate Bento again to resume";
            RefreshDesktopDividers();
            originals.Clear(); trayInterface.Refresh();
        }
    }
    public bool UpdateSettings(BentoSettings settings)
    {
        if (!settings.IsValid) { Report("Please check the settings values."); return false; }
        if (Dragging || activeNativeDrag != 0) { Report("Finish dragging before changing settings."); return false; }
        var old = Settings;
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
        tray?.ShowBalloonTip(4000, "Bento", text, Forms.ToolTipIcon.Info);
    }
    private void PresentDropPreview()
    {
        if (preview is null || nativeResizeWindow != 0) { dropPreview?.Hide(); return; }
        if (divider is not null && dividerMonitor is not null)
        {
            dropPreview?.Hide();
            var monitor = monitors.Single(m => m.Id == dividerMonitor);
            var boundary = Layout(monitor, preview).Dividers.Single(d => d.SplitId == divider.SplitId);
            dividers.FirstOrDefault(h => h.SplitId == divider.SplitId)?.PresentResize(boundary.Bounds);
            PlaceDividersBelowInterface();
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
                Settings.Animate && SystemParameters.ClientAreaAnimation, previewDestination?.Placement ?? Placement.Center, intent.Progress);
            return;
        }
        dropPreview?.Hide();
    }
    private void RefreshDesktopDividers()
    {
        if (Dragging) return;
        RefreshBackdrops();
        try
        {
            var wanted = automatic ? monitors.SelectMany(m => Layout(m, history.Current).Dividers.Select(d => (Monitor: m, Divider: d))).ToArray() : [];
            foreach (var handle in dividers.Where(h => !wanted.Any(w => w.Divider.SplitId == h.SplitId && w.Monitor.Id == h.MonitorId && w.Monitor.Scale == h.MonitorScale)).ToArray())
            { handle.Close(); dividers.Remove(handle); }
            foreach (var (monitor, boundary) in wanted)
            {
                var handle = dividers.FirstOrDefault(h => h.SplitId == boundary.SplitId && h.MonitorId == monitor.Id);
                if (handle is null) { handle = new DesktopDividerWindow(this, monitor, boundary); dividers.Add(handle); handle.Show(); }
                else handle.UpdateDivider(boundary);
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
        if (!disposed && automatic) RestoreAll();
        disposed = true;
        Microsoft.Win32.SystemEvents.UserPreferenceChanged -= AppearanceChanged;
        WallpaperContrast.Invalidate();
        timer.Stop(); events.Dispose(); transition?.Dispose(); CloseDesktopHelpers(); appWindow?.Close();
        CloseBackdrops();
        try { snapLease?.Dispose(); } catch { /* The recovery journal is kept for the next launch. */ }
        DesktopIntegration.UnregisterShortcut(source.Handle, 1); source.Dispose(); trayInterface.Dispose();
    }
}
