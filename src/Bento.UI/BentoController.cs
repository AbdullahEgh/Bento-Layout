using System.Windows.Interop;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace Bento.UI;

public sealed class BentoController : IDisposable
{
    private readonly HwndSource source;
    private readonly DesktopEvents events;
    private readonly Forms.NotifyIcon tray;
    private readonly WindowController native = new();
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
    private readonly HashSet<long> released = new();
    private bool automatic = true;
    private string? failedMembership;
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
        bool shortcut = DesktopIntegration.RegisterShortcut(source.Handle, 1, Settings.Modifiers, Settings.Key);
        int shortcutError = DesktopIntegration.ShortcutError;
        events = new DesktopEvents();
        events.NativeDrag += OnNativeDrag;
        var menu = new Forms.ContextMenuStrip();
        menu.Opening += (_, _) => RememberActiveWindow();
        menu.Items.Add("Open Bento", null, (_, _) => Dispatch(() => ShowInterface()));
        menu.Items.Add("Arrange all windows", null, (_, _) => Dispatch(AutoArrangeAll));
        menu.Items.Add("Undo", null, (_, _) => Dispatch(Undo));
        menu.Items.Add("Redo", null, (_, _) => Dispatch(Redo));
        menu.Items.Add("Refresh windows", null, (_, _) => Dispatch(Refresh));
        menu.Items.Add("Release active window", null, (_, _) =>
        {
            long id = lastActiveWindow;
            Dispatch(() => Remove(id));
        });
        menu.Items.Add("Settings", null, (_, _) => Dispatch(() => ShowInterface()));
        menu.Items.Add("Updates", null, (_, _) => Dispatch(() => ShowInterface("Updates")));
        menu.Items.Add("Restore all windows", null, (_, _) => Dispatch(RestoreAll));
        menu.Items.Add("Exit", null, (_, _) => Dispatch(() => Application.Current.Shutdown()));
        tray = new Forms.NotifyIcon { Icon = AppIcons.TrayIcon, Text = "Bento", ContextMenuStrip = menu, Visible = true };
        tray.DoubleClick += (_, _) => Dispatch(() => ShowInterface());
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
        if (appWindow?.IsVisible != true) return;
        var sibling = new WindowInteropHelper(appWindow).Handle;
        foreach (var handle in dividers) DesktopIntegration.PlaceBelow(new WindowInteropHelper(handle).Handle, sibling);
    }
    private void AppearanceChanged(object sender, Microsoft.Win32.UserPreferenceChangedEventArgs args) => Dispatch(() =>
    {
        AppTheme.Apply(Settings.Theme); WallpaperContrast.Invalidate();
        foreach (var handle in dividers) handle.RefreshContrast();
    });
    public void SetAutomatic(bool enabled)
    {
        if (enabled) { ArrangeDesktop(); return; }
        CancelDrag(); automatic = false; activeNativeDrag = 0;
        snapLease?.SetSuppressed(false); RefreshDesktopDividers();
    }

    private static void Dispatch(Action action) => Application.Current.Dispatcher.BeginInvoke(action);
    private nint WndProc(nint hwnd, int message, nint wparam, nint lparam, ref bool handled)
    {
        if (message == 0x312) { AutoArrangeAll(); handled = true; }
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
        automatic = true;
        snapLease?.SetSuppressed(Settings.SuppressWindowsSnap);
        Synchronize(geometryChanged);
        RefreshDesktopDividers();
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
    }
    private IReadOnlyList<AppWindow> DiscoverWindows(bool useCache = true) => windowSource?.Invoke() ?? WindowCatalog.Discover(includeMinimized: false,
        cache: useCache ? Windows.ToDictionary(w => w.Id) : null);
    public void AutoArrangeAll()
    {
        if (activeNativeDrag != 0) return;
        CancelDrag(); released.Clear(); automatic = true;
        snapLease?.SetSuppressed(Settings.SuppressWindowsSnap);
        Windows = DiscoverWindows(useCache: false); monitors = WindowCatalog.Monitors();
        Synchronize(rebuild: true);
    }
    private void Synchronize(bool rebuild = false)
    {
        string membership = string.Join(";", Windows.Where(w => !released.Contains(w.Id)).OrderBy(w => w.Id)
            .Select(w => $"{w.Id}:{w.ProcessId}:{w.MonitorId}:{w.Minimum}")) + string.Join(";", monitors);
        if (!rebuild && failedMembership == membership) return;
        try
        {
            var eligible = Windows.Where(w => !released.Contains(w.Id)).ToArray();
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
                // A manually dragged window remains in its committed monitor until the user moves it again.
                var additions = assigned.Where(w => !state.Windows.Any(n => n.WindowId == w.Id)).ToArray();
                var retained = LayoutEngine.Windows(existing).ToArray();
                if (rebuild || (existing is null && additions.Length > 0))
                {
                    var group = rebuild ? assigned.Select(w => WindowNode.Create(w.Id, w.Minimum)).ToArray()
                        : retained.Concat(additions.Select(w => WindowNode.Create(w.Id, w.Minimum))).ToArray();
                    state = state.WithRoot(monitor.Id, AutoLayout.Arrange(group, Area(monitor), Settings.Gap));
                    changed = true;
                }
                else foreach (var window in additions)
                {
                    existing = AutoLayout.Insert(existing, WindowNode.Create(window.Id, window.Minimum), Area(monitor), Settings.Gap);
                    state = state.WithRoot(monitor.Id, existing); changed = true;
                }
            }
            if (changed && !Commit(state, restoreRemoved: false)) failedMembership = membership;
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
        touchPoint = touch;
        timer.Interval = TimeSpan.FromMilliseconds(16);
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
            PresentDropPreview();
        }
        catch (Exception ex) when (ex is LayoutConstraintException or InvalidOperationException)
        { preview = null; previewDestination = null; dropPreview?.Hide(); Status = ex.Message; }
    }
    public void FinishDrag(PixelPoint? position = null)
    {
        UpdatePreview(position);
        var next = validPreview ? preview : null;
        bool nativeGesture = nativeStartBounds.HasValue;
        CancelDrag();
        bool applied = next is not null && Commit(next);
        if (!applied && nativeGesture)
        {
            try { Apply(history.Current, history.Current); RefreshDesktopDividers(); }
            catch (Exception ex) { Report(ex.Message); }
        }
    }
    public void CancelDrag()
    {
        incoming = null; divider = null; dividerMonitor = null; dragStart = null; preview = null;
        previewDestination = null;
        dragIntent.Reset(); intent = default; touchPoint = null;
        nativeResizeWindow = 0; validPreview = false;
        timer.Interval = TimeSpan.FromSeconds(1);
        dropPreview?.Hide();
        foreach (var handle in dividers) handle.Show();
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
    private bool Commit(WorkspaceState state, bool restoreRemoved = true)
    {
        try
        {
            Validate(state); Apply(history.Current, state, restoreRemoved); history.Commit(state); failedMembership = null;
            Status = "Windows arranged on the desktop.";
            RefreshDesktopDividers(); return true;
        }
        catch (Exception ex) { Report(ex.Message); return false; }
    }
    private void Apply(WorkspaceState previous, WorkspaceState next, bool restoreRemoved = true)
    {
        var ids = previous.Windows.Concat(next.Windows).Select(w => w.WindowId).Distinct().Where(WindowCatalog.Exists).ToArray();
        var rollback = ids.Select(native.Capture).ToArray();
        foreach (var snapshot in rollback)
            if (originals.TryGetValue(snapshot.WindowId, out var known) && known.ProcessId != snapshot.ProcessId)
                throw new InvalidOperationException("An application has restarted. Restart Bento to manage it again.");
        try
        {
            foreach (var id in next.Windows.Select(w => w.WindowId))
                if (!originals.ContainsKey(id)) originals[id] = native.Capture(id);
            var nextIds = next.Windows.Select(w => w.WindowId).ToHashSet();
            foreach (var old in previous.Windows.Where(w => restoreRemoved && !nextIds.Contains(w.WindowId)))
                if (originals.TryGetValue(old.WindowId, out var original)) native.Restore(original);
            var regions = monitors.SelectMany(m => Layout(m, next).Regions).ToArray();
            transition?.Dispose(); transition = null;
            if (Settings.Animate && SystemParameters.ClientAreaAnimation && regions.Length <= 16)
            {
                try { transition = new DesktopTransition(regions.Select(r => (r.Window.WindowId, native.VisibleBounds(r.Window.WindowId), r.Bounds)), Settings.AnimationMs); }
                catch { transition = null; /* Unsupported/protected thumbnails fall back to a direct placement. */ }
            }
            foreach (var region in regions)
                if (WindowCatalog.IsMinimized(region.Window.WindowId) || native.VisibleBounds(region.Window.WindowId) != region.Bounds)
                    native.Move(region.Window.WindowId, region.Bounds);
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
        if (Commit(new WorkspaceState()))
        {
            automatic = false; released.Clear();
            snapLease?.SetSuppressed(false);
            Status = "Windows restored · automatic arrangement paused · activate Bento again to resume";
            RefreshDesktopDividers();
        }
    }
    public bool UpdateSettings(BentoSettings settings)
    {
        if (!settings.IsValid) { Report("Please check the settings values."); return false; }
        if (Dragging || activeNativeDrag != 0) { Report("Finish dragging before changing settings."); return false; }
        var old = Settings;
        bool changed = settings.Key != old.Key || settings.Modifiers != old.Modifiers;
        if (changed)
        {
            DesktopIntegration.UnregisterShortcut(source.Handle, 1);
            if (!DesktopIntegration.RegisterShortcut(source.Handle, 1, settings.Modifiers, settings.Key))
            {
                DesktopIntegration.RegisterShortcut(source.Handle, 1, old.Modifiers, old.Key);
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
            if (changed) { DesktopIntegration.UnregisterShortcut(source.Handle, 1); DesktopIntegration.RegisterShortcut(source.Handle, 1, old.Modifiers, old.Key); }
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
        foreach (var monitor in monitors)
        {
            var layout = Layout(monitor, preview);
            PixelRect? bounds = incoming is not null
                ? previewDestination?.Monitor == monitor.Id ? SlotPreview.Bounds(dropTargetBounds, previewDestination.Value.Placement, Settings.Gap) : null
                : layout.Dividers.FirstOrDefault(d => d.SplitId == divider?.SplitId)?.Bounds;
            if (bounds is null) continue;
            (dropPreview ??= new DropPreviewWindow()).Present(bounds.Value, monitor.Scale,
                Settings.Animate && SystemParameters.ClientAreaAnimation);
            return;
        }
        dropPreview?.Hide();
    }
    private void RefreshDesktopDividers()
    {
        if (Dragging) return;
        foreach (var handle in dividers.ToArray()) handle.Close();
        dividers.Clear();
        if (!automatic) return;
        try
        {
            foreach (var monitor in monitors)
                foreach (var boundary in Layout(monitor, history.Current).Dividers)
                {
                    var handle = new DesktopDividerWindow(this, monitor, boundary);
                    dividers.Add(handle); handle.Show();
                }
            PlaceDividersBelowInterface();
        }
        catch (LayoutConstraintException) { /* Geometry may no longer fit after a display change. */ }
    }
    public void Dispose()
    {
        Microsoft.Win32.SystemEvents.UserPreferenceChanged -= AppearanceChanged;
        WallpaperContrast.Invalidate();
        timer.Stop(); events.Dispose(); transition?.Dispose(); CloseDesktopHelpers(); appWindow?.Close();
        try { snapLease?.Dispose(); } catch { /* The recovery journal is kept for the next launch. */ }
        DesktopIntegration.UnregisterShortcut(source.Handle, 1); source.Dispose(); tray.Dispose();
    }
}
