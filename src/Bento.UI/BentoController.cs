using System.Windows.Interop;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace Bento.UI;

public sealed partial class BentoController : IDisposable
{
    private readonly HwndSource source;
    private readonly DesktopEvents events;
    private readonly Forms.NotifyIcon tray;
    private readonly TrayInterface trayInterface;
    private readonly WindowController native;
    private readonly Dictionary<string, DesktopBackdropWindow> backdrops = new();
    private LayoutHistory history => session.History;
    private readonly Func<IReadOnlyList<AppWindow>>? windowSource;
    private readonly Func<long> clock;
    private readonly DragIntent dragIntent = new();
    private readonly SnapLease? snapLease;
    private DesktopTransition? transition;
    private BentoWindow? appWindow;
    private DropIntent intent;
    private Guid? seamTarget;
    private long seamEntered;
    private PixelRect dropTargetBounds;
    private PixelPoint? touchPoint;
    private Dictionary<long, (AppWindow Window, WindowSnapshot Snapshot)> minimizedByBento => session.Minimized;
    private HashSet<long> reopened => session.Reopened;
    public int MinimizedCount => minimizedByBento.Count;
    private HashSet<long> released => session.Released;
    private bool automatic { get => session.Active; set => session.Active = value; }
    private SessionLayoutSnapshot? lastBento { get => session.Remembered; set => session.Remembered = value; }
    private SessionLayoutSnapshot? savedSession { get => session.Saved; set => session.Saved = value; }
    private readonly ResizeHandleCache resizeHandles = new();
    private Guid? dividerSurface;
    private Dictionary<string, (LayoutNode Root, PixelRect Area, int Gap)> workAreaBaseline => session.WorkAreas;
    private bool reflowing;
    public bool HasSessionSave => savedSession is not null;
    private IEnumerable<SessionWindow> SessionWindows => Windows.Select(w => new SessionWindow(w.Id, w.ProcessId, w.Minimum));
    private bool disposed;
    private string? failedMembership { get => session.FailedMembership; set => session.FailedMembership = value; }
    private long? rejectedWindow;
    private sealed class PlacementFailure(long id, Exception cause) : Exception(cause.Message, cause) { public long WindowId => id; }
    private Dictionary<long, WindowSnapshot> originals => session.Originals;
    private readonly List<DesktopDividerWindow> dividers = new();
    private readonly DropPreviewLayout dropPreview = new();
    private readonly DispatcherTimer timer;
    private IReadOnlyList<DesktopMonitor> monitors { get => session.Monitors; set => session.Monitors = value; }
    private WorkspaceState? preview;
    private (string Monitor, Guid? Target, Placement Placement, bool Section)? previewDestination;
    private readonly GestureProposalCache<(string Monitor, Guid? Target, Placement Placement, bool Section), WorkspaceState> dropProposals = new();
    private long completingNativeGesture;
    private WindowNode? incoming;
    private long activeNativeDrag;
    private long lastActiveWindow { get => session.LastActive; set => session.LastActive = value; }
    private Dictionary<long, long> lastInteraction => session.Interactions;
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
    public IReadOnlyList<AppWindow> Windows { get => session.Windows; private set => session.Windows = value; }
    public bool Dragging => incoming is not null || divider is not null || nativeResizeWindow != 0;
    public WorkspaceState DisplayState => preview ?? history.Current;
    public string Status { get; private set; } = "";
    public bool Automatic => automatic;
    public int ManagedCount => history.Current.Windows.Count();

    public BentoController(Func<IReadOnlyList<AppWindow>>? windowSource = null, BentoSettings? settings = null, Func<long>? clock = null, IDesktopEnvironment? desktopEnvironment = null, SnapLease? snapLease = null)
    {
        this.windowSource = windowSource;
        this.snapLease = snapLease;
        this.clock = clock ?? (() => Environment.TickCount64);
        this.desktopEnvironment = desktopEnvironment ?? (windowSource is null ? new DesktopEnvironment() : null);
        native = new WindowController(CanWriteNative);
        try
        {
        if (settings is not null) Settings = settings;
        if (windowSource is null)
        {
            this.snapLease ??= new SnapLease(Path.Combine(BentoSettings.DataDirectory, "snap-lease.txt"));
            taskbarLease = new TaskbarLease(Path.Combine(BentoSettings.DataDirectory, "taskbar-lease.json"));
        }
        source = new HwndSource(new HwndSourceParameters("Bento hotkeys") { Width = 0, Height = 0, WindowStyle = 0 });
        source.AddHook(WndProc);
        bool shortcut = !Settings.ShortcutEnabled || DesktopIntegration.RegisterShortcut(source.Handle, 1, Settings.Modifiers, Settings.Key);
        int shortcutError = DesktopIntegration.ShortcutError;
        events = new DesktopEvents();
        events.NativeDrag += OnNativeDrag;
        events.ObserverFailed += ex => Dispatch(() => Report(ex.Message), scoped: false);
        events.ForegroundChanged += () => Dispatch(OnForeground);
        events.WindowsChanged += () => Dispatch(RequestMembershipRefresh);
        events.WindowInvalidated += id => Dispatch(() => ForgetWindow(id), scoped: false);
        events.OverviewChanged += value => Dispatch(() => { overview = value; EnsureDesktop(); }, scoped: false);
        events.DesktopChanged += () => Dispatch(() => EnsureDesktop(), scoped: false);
        trayInterface = new TrayInterface(this, RememberActiveWindow, () => lastActiveWindow);
        tray = trayInterface.Icon;
        timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        timer.Tick += (_, _) => Tick(); timer.Start();
        ConfigurePlatformTimers();
        Microsoft.Win32.SystemEvents.UserPreferenceChanged += AppearanceChanged;
        if (!shortcut) Report($"Could not register {Settings.Shortcut} (Windows error {shortcutError}). Choose another shortcut in tray settings.");
        // Session overrides are acquired only after activation on a proven desktop.
        }
        catch
        {
            disposed = true;
            foreach (var release in new Action[] {
                () => timer?.Stop(), () => platformTimer.Stop(), () => membershipTimer.Stop(), () => geometryTimer.Stop(), () => settledTimer.Stop(),
                () => events?.Dispose(), () => trayInterface?.Dispose(), () => taskbarLease?.Dispose(), () => snapLease?.Dispose(), () => desktopEnvironment?.Dispose(),
                () => { if (source is not null) { DesktopIntegration.UnregisterShortcut(source.Handle, 1); source.Dispose(); } } })
                try { release(); } catch { /* Preserve the initialization failure. */ }
            Microsoft.Win32.SystemEvents.UserPreferenceChanged -= AppearanceChanged;
            throw;
        }
    }

    public void ShowInterface(string page = "Workspace")
    {
        if (disposed) return;
        bool known = EnsureDesktop();
        // Reusing a window on a different desktop can make Windows switch the
        // user back there. Move only our own settings HWND after proving the
        // current identity; create a fresh window when that proof is unavailable.
        if (!known && appWindow is not null) { appWindow.Close(); appWindow = null; }
        bool createdHere = appWindow is null;
        if (appWindow is null)
        {
            var created = new BentoWindow(this); appWindow = created;
            created.Closed += (_, _) => { if (ReferenceEquals(appWindow, created)) appWindow = null; };
            created.Activated += (_, _) => PlaceDividersBelowInterface();
        }
        if (!createdHere && known && desktopEnvironment is not null && sessions.Desktop is { } desktop)
        {
            var handle = new WindowInteropHelper(appWindow).EnsureHandle().ToInt64();
            if (!desktopEnvironment.Contains(desktop, handle) && !desktopEnvironment.MoveHelper(handle, desktop))
            { appWindow.Close(); appWindow = null; ShowInterface(page); return; }
        }
        appWindow.SelectPage(page); appWindow.Show(); appWindow.WindowState = WindowState.Normal; appWindow.Activate();
        PlaceDividersBelowInterface();
    }
    private void PlaceDividersBelowInterface()
    {
        if (!HelpersAllowed) return;
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
        if (!EnsureDesktop()) return;
        if (enabled == automatic) return;
        if (enabled) { ArrangeDesktop(); return; }
        Deactivate(restorePositions: savedSession is null);
    }
    public void ToggleBento() { if (EnsureDesktop()) SetAutomatic(!automatic); }
    public void SaveBento()
    {
        if (!EnsureDesktop() || !automatic || Dragging || !history.Current.Windows.Any()) return;
        savedSession = CaptureSessionLayout();
        Report("Layout saved for this session. Turning Bento off will keep window positions.");
    }
    public void ClearSessionSave()
    {
        if (!EnsureDesktop()) return;
        savedSession = null;
        Report("Session save cleared. Turning Bento off restores original positions.");
    }
    public void UseSessionSave()
    {
        if (!EnsureDesktop() || Dragging || activeNativeDrag != 0 || savedSession is null) return;
        if (session.Fullscreen.Count > 0) { Report("Leave fullscreen before using the saved layout."); return; }
        Windows = DiscoverWindows(useCache: false); monitors = WindowCatalog.Monitors();
        var next = savedSession.Reconcile(SessionWindows, monitors.Select(m => m.Id));
        if (!next.Windows.Any()) { Report("The saved windows are no longer available."); return; }
        bool paused = Paused;
        if (!Commit(next)) return;
        if (paused) { session.Pause.Exit(); ClosePausedShades(); UpdatePausePointer(); }
        automatic = true; ScheduleSettled();
        released.UnionWith(Windows.Select(w => w.Id).Except(next.Windows.Select(w => w.WindowId)).Except(minimizedByBento.Keys));
        released.ExceptWith(next.Windows.Select(w => w.WindowId));
        UpdateLeases();
        RefreshDesktopDividers(); trayInterface.Refresh();
    }

    private void Dispatch(Action action, bool scoped = true)
    {
        if (disposed) return;
        long revision = sessions.Revision;
        Application.Current.Dispatcher.BeginInvoke(new Action(() => { if (!disposed && (!scoped || revision == sessions.Revision)) action(); }));
    }
    private nint WndProc(nint hwnd, int message, nint wparam, nint lparam, ref bool handled)
    {
        if (disposed) return 0;
        if (message == 0x312) { if (Settings.ShortcutEnabled) ToggleBento(); handled = true; }
        if (message is 0x7E or 0x2E0 or 0x1A)
            Dispatch(RequestGeometryRefresh, scoped: false);
        return 0;
    }

    private void ArrangeDesktopCore()
    {
        if (!EnsureDesktop()) return;
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
            failedMembership = null;
            WorkspaceState? resume = lastBento?.Reconcile(SessionWindows, monitors.Select(m => m.Id));
            if (resume is not null)
            {
                foreach (var leaf in resume.Windows.ToArray()) if (!Windows.Any(w => w.Id == leaf.WindowId)) resume = resume.Remove(leaf.WindowId);
                foreach (string id in resume.Roots.Keys.Where(id => !monitors.Any(m => m.Id == id)).ToArray()) resume = resume.WithRoot(id, null);
                if (Commit(resume)) geometryChanged = false;
            }
        }
        automatic = true;
        foreach (var window in Windows.Where(w => session.OverflowBeforeOff.GetValueOrDefault(w.Id) == w.ProcessId && !released.Contains(w.Id)).ToArray())
        {
            try
            {
                var snapshot = native.Capture(window.Id); originals.TryAdd(window.Id, snapshot);
                native.Minimize(window.Id); if (WindowCatalog.IsMinimized(window.Id)) minimizedByBento[window.Id] = (window, snapshot);
            }
            catch (Exception ex) { Report(ex.Message); }
        }
        UpdateLeases();
        RefreshFullscreenReservations();
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
        dropPreview.Close(); CloseWaiting();
    }
    public void Refresh()
    {
        if (!EnsureDesktop()) return;
        Windows = DiscoverWindows(useCache: false); RememberActiveWindow();
        RefreshFullscreenReservations();
        if (Paused) RefreshPausedShades();
        else if (automatic && !Dragging && activeNativeDrag == 0) { ReapplyCurrentSession(); Synchronize(); }
        PlaceDividersBelowInterface();
    }
    private IReadOnlyList<AppWindow> DiscoverWindows(bool useCache = true)
    {
        var discovered = windowSource?.Invoke() ?? WindowCatalog.Discover(includeMinimized: false, cache: useCache ? Windows.ToDictionary(w => w.Id) : null);
        foreach (var known in Windows.Where(old => discovered.Any(w => w.Id == old.Id && w.ProcessId != old.ProcessId)).ToArray()) ForgetWindow(known.Id);
        var visible = discovered.Where(w => CurrentMember(w.Id)).Select(w =>
        {
            var reported = windowSource is null ? w : w with { ReportedMinimum = w.Minimum };
            return reported with { Minimum = native.EffectiveMinimum(reported) };
        }).ToList();
        foreach (var known in session.FullscreenKnown.Values)
            if (!visible.Any(w => w.Id == known.Id) && WindowCatalog.Exists(known.Id) && WindowCatalog.ProcessId(known.Id) == known.ProcessId && !WindowCatalog.IsMinimized(known.Id) && CurrentMember(known.Id)) visible.Add(known);
        foreach (var (id, entry) in minimizedByBento.ToArray())
        {
            if (!WindowCatalog.Exists(id) || WindowCatalog.ProcessId(id) != entry.Snapshot.ProcessId) { ForgetWindow(id); continue; }
            if (!CurrentMember(id)) continue;
            if (visible.Any(w => w.Id == id) && !WindowCatalog.IsMinimized(id))
            { reopened.Add(id); session.ResumeHeld.Remove(id); session.OverflowBeforeOff.Remove(id); minimizedByBento.Remove(id); }
            else if (WindowCatalog.IsMinimized(id) && !visible.Any(w => w.Id == id)) visible.Add(entry.Window);
        }
        native.RetainConstraints(visible.Select(w => w.Id).Concat(sessions.All.SelectMany(s => s.Windows).Select(w => w.Id)).Where(WindowCatalog.Exists).ToHashSet());
        return visible;
    }
    public void AutoArrangeAll()
    {
        if (!EnsureDesktop()) return;
        if (activeNativeDrag != 0) return;
        CancelDrag(); session.Pause.Exit(); ClosePausedShades(); UpdatePausePointer(); released.Clear(); session.ResumeHeld.Clear(); session.OverflowBeforeOff.Clear();
        automatic = true;
        UpdateLeases();
        Windows = DiscoverWindows(useCache: false); monitors = WindowCatalog.Monitors();
        Synchronize(rebuild: true);
        trayInterface.Refresh();
    }
    private void Synchronize(bool rebuild = false, HashSet<long>? excluded = null)
    {
        if (!EnsureDesktop() || !automatic || Paused) return;
        if (!rebuild && history.Current.Windows.Any(w => !Windows.Any(live => live.Id == w.WindowId) && WindowCatalog.Exists(w.WindowId) && !WindowCatalog.IsMinimized(w.WindowId)))
        { Status = "Waiting for hidden windows or the desktop transition to settle."; return; }
        string membership = string.Join(";", Windows.Where(w => !released.Contains(w.Id)).OrderBy(w => w.Id)
            .Select(w => $"{w.Id}:{w.ProcessId}:{w.MonitorId}:{w.Minimum}")) + string.Join(";", monitors);
        if (!rebuild && reopened.Count == 0 && failedMembership == membership) return;
        try
        {
            var eligible = Windows.Where(w => !released.Contains(w.Id) && !session.ResumeHeld.Contains(w.Id) && !session.Fullscreen.Contains(w.Id) && !(excluded?.Contains(w.Id) ?? false)).ToArray();
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
                var root = AutoLayout.Fitting(group, Area(monitor), Gap(monitor), rebuild ? null : existing, priority, oldest);
                if (!Settings.MinimizeOverflow && LayoutEngine.Windows(root).Count() != group.Length)
                    throw new LayoutConstraintException("These windows cannot all fit. Enable overflow minimization or free some space; the previous layout was kept.");
                if (!Equals(root, existing)) changed = true;
                state = state.WithRoot(monitor.Id, root);
            }
            if (changed && !Commit(state, restoreRemoved: session.Fullscreen.Count == 0))
            {
                excluded ??= new();
                if (rejectedWindow is long failed && excluded.Add(failed) && excluded.Count <= Windows.Count)
                { Synchronize(rebuild, excluded); return; }
                failedMembership = membership; return;
            }
            var included = state.Windows.Select(w => w.WindowId).ToHashSet();
            foreach (long id in included) minimizedByBento.Remove(id);
            if (Settings.MinimizeOverflow)
                foreach (var window in Windows.Where(w => !released.Contains(w.Id) && !session.Fullscreen.Contains(w.Id) && !session.ResumeHeld.Contains(w.Id) && !included.Contains(w.Id) && !minimizedByBento.ContainsKey(w.Id)))
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
            reopened.Clear(); RefreshWaiting();
        }
        catch (Exception ex) { failedMembership = membership; Report(ex.Message); }
    }
    public int Gap(DesktopMonitor monitor) => Math.Max(0, (int)Math.Round(Settings.Gap * monitor.Scale));
    public PixelRect Area(DesktopMonitor monitor) => monitor.WorkArea.Inset((int)Math.Round(Settings.Margin * monitor.Scale));
    public LayoutResult Layout(DesktopMonitor monitor, WorkspaceState? state = null)
    {
        (state ?? DisplayState).Roots.TryGetValue(monitor.Id, out var root);
        return LayoutEngine.Calculate(root, Area(monitor), Gap(monitor));
    }
    public void BeginDrag(long id)
    {
        if (!EnsureDesktop() || !automatic || Paused) return;
        CancelSettled(); CloseJoinCues();
        var window = Windows.FirstOrDefault(w => w.Id == id);
        if (window is null) return;
        CancelDrag(); lastActiveWindow = id; lastInteraction[id] = clock();
        transition?.Dispose();
        incoming = history.Current.Windows.FirstOrDefault(w => w.WindowId == id) ?? WindowNode.Create(id, window.Minimum);
        timer.Interval = TimeSpan.FromMilliseconds(16);
        foreach (var handle in dividers) handle.Hide();
        UpdatePreview();
    }
    public void BeginDivider(DesktopMonitor monitor, Divider value, PixelPoint? touch = null)
    {
        if (!EnsureDesktop() || !automatic || Paused) return;
        CancelSettled(); CloseJoinCues();
        CancelDrag();
        dividerSurface = value.SplitId;
        var point = touch ?? WindowCatalog.Cursor;
        var handles = Handles(monitor, history.Current); gestureHandles = handles;
        var selected = ResizeHandles.Hit(handles, point, monitor.Scale);
        divider = selected?.Divider ?? value; dividerMonitor = monitor.Id;
        dragStart = selected is null ? history.Current : history.Current.WithRoot(monitor.Id, selected.Root);
        gestureHandlesRoot = dragStart.Roots[monitor.Id];
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
        if (!EnsureDesktop() || !automatic || Paused) return;
        CancelSettled(); CloseJoinCues();
        CancelDrag();
        if (!history.Current.Windows.Any(w => w.WindowId == id)) return;
        nativeResizeWindow = id; dragStart = history.Current;
        var monitor = monitors.FirstOrDefault(m => LayoutEngine.Windows(history.Current.Roots.GetValueOrDefault(m.Id)).Any(w => w.WindowId == id));
        if (monitor is not null) { gestureHandles = Handles(monitor, history.Current); gestureHandlesRoot = history.Current.Roots[monitor.Id]; }
        timer.Interval = TimeSpan.FromMilliseconds(16);
        foreach (var handle in dividers) handle.Hide();
    }
    public void PreviewDrag(PixelPoint point) { if (touchPoint.HasValue) touchPoint = point; UpdatePreview(point); }
    private void Tick()
    {
        if (!EnsureDesktop()) return;
        RefreshFullscreenReservations();
        if (Paused)
        {
            Windows = DiscoverWindows();
            var live = session.Pause.Members.Where(id => WindowCatalog.Exists(id) && !WindowCatalog.IsMinimized(id)).ToHashSet();
            session.Pause.Retain(live);
            foreach (var missing in history.Current.Windows.Where(w => !WindowCatalog.Exists(w.WindowId) || WindowCatalog.IsMinimized(w.WindowId)).ToArray()) history.Commit(history.Current.Remove(missing.WindowId));
            RefreshPausedShades(); ApplyPendingInteractionState(); return;
        }
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
        ReapplyCurrentSession(); Synchronize();
        PlaceDividersBelowInterface();
    }
    private void RefreshMonitorGeometry()
    {
        if (disposed) return;
        var latest = WindowCatalog.Monitors();
        if (monitors.SequenceEqual(latest) || activeNativeDrag != 0 || Dragging) return;
        foreach (var monitor in monitors)
            if (history.Current.Roots.GetValueOrDefault(monitor.Id) is { } root && !workAreaBaseline.ContainsKey(monitor.Id))
                workAreaBaseline[monitor.Id] = (root, Area(monitor), Gap(monitor));
        foreach (var window in Windows) native.ForgetWindow(window.Id);
        refusedWaiting.Clear();
        monitors = latest;
        foreach (var id in workAreaBaseline.Keys.Where(id => !latest.Any(m => m.Id == id)).ToArray()) workAreaBaseline.Remove(id);
        if (!automatic || Paused) return;
        Windows = DiscoverWindows(useCache: false);
        reflowing = true;
        try
        {
            var state = ReflowCurrentAreas(history.Current);
            if (Commit(state)) Synchronize();
        }
        catch (LayoutConstraintException) { Synchronize(rebuild: true); }
        finally { reflowing = false; }
    }
    private void OnNativeDrag(long id, bool starting) => Dispatch(() =>
    {
        if (!EnsureDesktop()) return;
        if (starting)
        {
            if (!automatic) return;
            try
            {
                // Reuse known minimum sizes: querying every application synchronously here delays the native drag.
                Windows = DiscoverWindows();
                bool fullscreen = session.Fullscreen.Contains(id) || LooksFullscreen(id);
                activeNativeDrag = id; nativeStartBounds = null;
                if (fullscreen || Paused || released.Contains(id) || !Windows.Any(w => w.Id == id))
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
        finally { nativeStartBounds = null; ApplyPendingInteractionState(); RequestMembershipRefresh(); }
    });
    private void UpdatePreview(PixelPoint? position = null)
    {
        if (!EnsureDesktop() || !automatic || Paused) return;
        var point = position ?? touchPoint ?? WindowCatalog.Cursor;
        previewDestination = null;
        preview = null; validPreview = false;
        try
        {
            if (nativeResizeWindow != 0)
            {
                var sourceMonitor = monitors.FirstOrDefault(m => LayoutEngine.Windows(dragStart!.Roots.GetValueOrDefault(m.Id))
                    .Any(w => w.WindowId == nativeResizeWindow));
                if (sourceMonitor is null || !WindowCatalog.Exists(nativeResizeWindow)) { dropPreview.Hide(); return; }
                var root = dragStart!.Roots[sourceMonitor.Id]!;
                var actual = native.VisibleBounds(nativeResizeWindow);
                var window = Windows.First(w => w.Id == nativeResizeWindow);
                var leaf = LayoutEngine.Windows(root).Single(w => w.WindowId == nativeResizeWindow);
                var minimum = native.ObserveUserFrame(window, actual);
                root = LayoutEngine.Replace(root, leaf.Id, leaf with { Minimum = minimum });
                preview = dragStart.WithRoot(sourceMonitor.Id, LayoutEngine.ResizeWindow(root, nativeResizeWindow, actual, Area(sourceMonitor), Gap(sourceMonitor), (int)Math.Round(12 * sourceMonitor.Scale)));
            }
            else if (divider is not null && dividerMonitor is not null)
            {
                var root = dragStart!.Roots[dividerMonitor]!;
                var monitor = monitors.Single(m => m.Id == dividerMonitor);
                var candidate = LayoutEngine.ResizeDivider(root, divider, point, dividerStart, Gap(monitor));
                preview = dragStart.WithRoot(dividerMonitor, ReferenceEquals(candidate, root) ? root : LayoutInteraction.SnapSeam(candidate, divider.SplitId,
                    Area(monitor), Gap(monitor), (int)Math.Round(12 * monitor.Scale)));
            }
            else if (incoming is not null)
            {
                if (dropProposals.Use(history.Current)) dragIntent.Reset();
                var monitor = monitors.FirstOrDefault(m => m.Bounds.Contains(point));
                if (monitor is null) { dragIntent.Reset(); dropPreview.Hide(); return; }
                var sourceRoot = history.Current.Roots.GetValueOrDefault(monitor.Id);
                var edge = LayoutInteraction.ScreenEdge(monitor.Bounds, point, (int)Math.Round(20 * monitor.Scale));
                if (edge is { } sectionEdge && sourceRoot is not null && LayoutEngine.Windows(sourceRoot).Any(w => w.WindowId == incoming.WindowId))
                {
                    dragIntent.Reset(); intent = new(sectionEdge, 0, false);
                    previewDestination = (monitor.Id, null, sectionEdge, true);
                    if (!dropProposals.TryGetValue(previewDestination.Value, out var section))
                    {
                        var moved = LayoutInteraction.MoveSection(sourceRoot, incoming.WindowId, sectionEdge, Area(monitor), Gap(monitor));
                        section = moved is null ? null : history.Current.WithRoot(monitor.Id, moved);
                        dropProposals[previewDestination.Value] = section;
                    }
                    if (section is null) { dropPreview.Hide(); return; }
                    preview = section; validPreview = true; PresentDropPreview(); return;
                }
                if (!Area(monitor).Contains(point)) { dragIntent.Reset(); dropPreview.Hide(); return; }
                var target = Layout(monitor, history.Current).Regions.FirstOrDefault(r => r.Bounds.Contains(point));
                if (target?.Window.WindowId == incoming.WindowId) { dragIntent.Reset(); dropPreview.Hide(); return; }
                bool seamSwap = false;
                if (target is null && history.Current.Windows.Any(w => w.WindowId == incoming.WindowId)
                    && Layout(monitor, history.Current).Dividers.Any(d => d.Bounds.Contains(point)))
                {
                    target = Layout(monitor, history.Current).Regions.Where(r => r.Window.WindowId != incoming.WindowId)
                        .OrderBy(r => Math.Pow(Math.Max(r.Bounds.X - point.X, Math.Max(0, point.X - r.Bounds.Right)), 2)
                            + Math.Pow(Math.Max(r.Bounds.Y - point.Y, Math.Max(0, point.Y - r.Bounds.Bottom)), 2)).FirstOrDefault();
                    if (target is not null)
                    {
                        if (seamTarget != target.Window.Id) { seamTarget = target.Window.Id; seamEntered = clock(); }
                        if (clock() - seamEntered < 250) { dropPreview.Hide(); return; }
                        seamSwap = true;
                    }
                }
                else seamTarget = null;
                if (target is null && history.Current.Roots.GetValueOrDefault(monitor.Id) is not null) { dragIntent.Reset(); dropPreview.Hide(); return; }
                var bounds = target?.Bounds ?? Area(monitor);
                dropTargetBounds = bounds;
                intent = target is null || seamSwap ? new(Placement.Center, 0, false) :
                    dragIntent.Update(monitor.Id, target.Window.Id, bounds, point, clock(), Settings.SplitHoldMs, monitor.Scale);
                var placement = intent.Placement;
                if (waitingIncoming == 0 && placement == Placement.Center && target is not null && !history.Current.Windows.Any(w => w.WindowId == incoming.WindowId))
                    placement = bounds.Width >= bounds.Height ? Placement.Right : Placement.Bottom;
                var destinationKey = (monitor.Id, target?.Window.Id, placement, false);
                previewDestination = destinationKey;
                if (dropProposals.TryGetValue(destinationKey, out var cached))
                {
                    if (cached is null) throw new LayoutConstraintException("This destination cannot fit these windows.");
                    preview = cached; validPreview = true; PresentDropPreview(); return;
                }
                preview = DropPlanning.Place(history.Current, monitor.Id, target?.Window.Id, incoming, placement,
                    monitors.ToDictionary(m => m.Id, Area), monitors.ToDictionary(m => m.Id, Gap),
                    otherAxis: waitingIncoming == 0 && intent.Placement == Placement.Center && !history.Current.Windows.Any(w => w.WindowId == incoming.WindowId));
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
            Validate(preview);
            if (waitingIncoming != 0 && refusedWaiting.TryGetValue(waitingIncoming, out var refused) &&
                monitors.SelectMany(m => Layout(m, preview).Regions).Any(r => r.Window.WindowId == waitingIncoming && refused.Contains(r.Bounds)))
                throw new LayoutConstraintException("This window refused this slot. Choose a larger slot.");
            validPreview = true;
            if (nativeResizeWindow != 0)
            {
                var monitor = monitors.FirstOrDefault(m => LayoutEngine.Windows(preview.Roots.GetValueOrDefault(m.Id)).Any(w => w.WindowId == nativeResizeWindow));
                if (monitor is not null && preview.Roots[monitor.Id] is { } root) UpdateNativeJoinCue(monitor, root, nativeResizeWindow, native.VisibleBounds(nativeResizeWindow));
            }
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
                dropPreview.Present(monitors.SelectMany(m => Layout(m, history.Current).Regions
                    .Where(r => r.Bounds != dropTargetBounds).Select(r => new PreviewSlot(r.Window.WindowId, m.Id, r.Bounds)))
                    .Append(new PreviewSlot(incoming.WindowId, monitor.Id, dropTargetBounds)).ToArray(), monitors, incoming.WindowId, false, conflict: true);
            else dropPreview.Hide();
            Status = ex.Message;
        }
    }
    public void FinishDrag(PixelPoint? position = null)
    {
        if (!EnsureDesktop() || !automatic || Paused || !Dragging) return;
        var owner = session;
        completingNativeGesture = nativeResizeWindow != 0 ? nativeResizeWindow : incoming?.WindowId ?? 0;
        try
        {
            // The final native resize sample can cover the screen. It is still
            // the user's known resize gesture, not a new fullscreen transition.
            UpdatePreview(position);
            var next = validPreview ? preview : null;
            bool nativeGesture = nativeStartBounds.HasValue;
            var liveStart = liveResizeStart;
            long waiting = waitingIncoming;
            ClearDrag(restoreLive: false);
            bool applied = next is not null && (waiting != 0 ? CommitWaiting(next, waiting) : Commit(next, animate: liveStart is null));
            string failure = Status;
            if (ReferenceEquals(owner, session))
            {
                if (!applied && liveStart is not null) RestoreLiveResize(liveStart);
                if (!applied && nativeGesture)
                {
                    try { Apply(history.Current, history.Current); }
                    catch (Exception ex) { Report(ex.Message); }
                }
                if (!applied && next is not null && waiting == 0) Report(failure);
            }
            if (!applied) { CloseJoinCues(); RefreshDesktopDividers(); }
        }
        finally { completingNativeGesture = 0; RequestMembershipRefresh(); }
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
        if (restoreLive) CloseJoinCues();
        if (restoreLive && snapshots is not null) RestoreLiveResize(snapshots);
        incoming = null; divider = null; dividerSurface = null; dividerMonitor = null; dragStart = null; preview = null;
        previewDestination = null; dropProposals.Clear();
        dragIntent.Reset(); intent = default; touchPoint = null; seamTarget = null;
        nativeResizeWindow = 0; validPreview = false; gestureHandles = null; gestureHandlesRoot = null;
        timer.Interval = TimeSpan.FromSeconds(1);
        dropPreview.Hide();
        if (restoreLive)
            foreach (var handle in dividers) { handle.ResetPresentation(); handle.Show(); }
        PlaceDividersBelowInterface();
        Dispatch(ApplyPendingInteractionState);
    }
    public void Remove(long id)
    {
        if (!EnsureDesktop() || !automatic || Paused) return;
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
        var owner = session;
        try
        {
            Validate(state); Apply(history.Current, state, restoreRemoved, animate); state = AlignNativeSeams(state, owner);
            if (!ReferenceEquals(owner, session)) throw new InvalidOperationException("Desktop changed before commit.");
            history.Commit(state); failedMembership = null; session.NeedsReapply = false;
            foreach (var region in monitors.SelectMany(m => Layout(m, state).Regions))
                session.AppliedFrames[region.Window.WindowId] = (region.Bounds, WindowCatalog.HasCaption(region.Window.WindowId));
            if (!reflowing) workAreaBaseline.Clear();
            Status = "Windows arranged on the desktop.";
            RefreshDesktopDividers(); ScheduleSettled(); return true;
        }
        catch (Exception ex) { Status = ex.Message; rejectedWindow = (ex as PlacementFailure)?.WindowId; if (rejectedWindow is null) Report(ex.Message); return false; }
    }
    private void Apply(WorkspaceState previous, WorkspaceState next, bool restoreRemoved = true, bool animate = true, DesktopSession? expectedOwner = null)
    {
        var owner = expectedOwner ?? session;
        if (!ReferenceEquals(owner, session) || !EnsureDesktop() || !ReferenceEquals(owner, session)) throw new InvalidOperationException("Desktop changed; placement deferred.");
        CancelSettled();
        var ids = previous.Windows.Concat(next.Windows).Select(w => w.WindowId).Distinct().Where(WindowCatalog.Exists).ToArray();
        var rollback = ids.Select(native.Capture).ToArray();
        var appliedBefore = owner.AppliedFrames.ToDictionary();
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
            if (!organizing && animate && Settings.Animate && SystemParameters.ClientAreaAnimation && regions.Length + removed.Length <= 16)
            {
                try
                {
                    var moves = regions.Select(r => (r.Window.WindowId, native.VisibleBounds(r.Window.WindowId), r.Bounds))
                        .Concat(removed.Select(s => (s.WindowId, native.VisibleBounds(s.WindowId), s.VisibleBounds)));
                    transition = new DesktopTransition(moves, Settings.AnimationMs);
                }
                catch { transition = null; }
            }
            foreach (var original in removed) { native.Restore(original); owner.AppliedFrames.Remove(original.WindowId); }
            foreach (var region in regions)
            {
                long id = region.Window.WindowId;
                try
                {
                    if (!CanWriteNative(id)) throw new InvalidOperationException("The window or its desktop is no longer available for arrangement.");
                    PixelRect? applied = owner.AppliedFrames.TryGetValue(id, out var prior) ? prior.Slot : null;
                    if (WindowCatalog.IsMinimized(id) || NativeFrameFit.NeedsPlacement(native.VisibleBounds(id), region.Bounds, applied)) native.Move(id, region.Bounds, learnMinimum: !reflowing);
                    // Keep provenance current for Settings and rollback paths too,
                    // which can apply geometry without a history commit.
                    owner.AppliedFrames[id] = (region.Bounds, WindowCatalog.HasCaption(id));
                }
                catch (Exception ex) { throw new PlacementFailure(id, ex); }
            }
            transition?.Play();

        }
        catch
        {
            transition?.Dispose(); transition = null;
            if (ReferenceEquals(owner, session))
            {
                foreach (var snapshot in rollback) { try { native.Restore(snapshot); } catch { /* Best effort if a process exits or denies access. */ } }
                owner.AppliedFrames.Clear(); foreach (var entry in appliedBefore) owner.AppliedFrames[entry.Key] = entry.Value;
            }
            throw;
        }
    }
    public void Undo() => NavigateHistory(false);
    public void Redo() => NavigateHistory(true);
    private void NavigateHistory(bool redo)
    {
        if (!EnsureDesktop() || !automatic || Paused) return;
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
        if (!EnsureDesktop()) return;
        CancelSettled(); session.Pause.Exit(); ClosePausedShades(); UpdatePausePointer(); CloseJoinCues(); CancelDrag();
        var previous = history.Current;
        if (previous.Windows.Any() || session.FullscreenReference is not null) lastBento = session.FullscreenReference ?? new(previous, SessionWindows);
        session.OverflowBeforeOff.Clear();
        foreach (var (id, entry) in minimizedByBento) session.OverflowBeforeOff[id] = entry.Snapshot.ProcessId;
        int failures = 0;
        transition?.Dispose(); transition = null;
        var returning = restorePositions ? originals.Values.Where(s => !session.Fullscreen.Contains(s.WindowId)).ToArray()
            : minimizedByBento.Values.Select(e => e.Snapshot).ToArray();
        if (Settings.Animate && SystemParameters.ClientAreaAnimation && returning.Length is > 0 and <= 16)
            try { transition = new DesktopTransition(returning.Where(s => CanWriteNative(s.WindowId)).Select(s =>
                (s.WindowId, native.VisibleBounds(s.WindowId), s.VisibleBounds)), Math.Max(320, Settings.AnimationMs)); }
            catch { transition = null; }
        var restored = new HashSet<long>();
        if (restorePositions)
            foreach (var (id, snapshot) in originals.ToArray())
            {
                if (!WindowCatalog.Exists(id) || WindowCatalog.ProcessId(id) != snapshot.ProcessId) { originals.Remove(id); continue; }
                if (session.Fullscreen.Contains(id)) continue; // Preserve its reservation; never force fullscreen to exit.
                try { native.Restore(snapshot); restored.Add(id); originals.Remove(id); }
                catch (Exception ex) { failures++; Status = ex.Message; }
            }
        foreach (var (id, entry) in minimizedByBento.ToArray())
        {
            if (restored.Contains(id)) { minimizedByBento.Remove(id); continue; }
            if (restorePositions && originals.ContainsKey(id)) continue; // Original restoration failed; keep it retryable.
            try { native.Restore(entry.Snapshot); minimizedByBento.Remove(id); }
            catch (Exception ex) { failures++; Status = ex.Message; }
        }
        if (failures > 0) { transition?.Dispose(); transition = null; }
        else transition?.Play();
        if (restorePositions) session.AppliedFrames.Clear();
        automatic = false; session.NeedsReapply = false; CancelSettled(); reopened.Clear();
        history.Commit(new WorkspaceState()); UpdateLeases(); RefreshDesktopDividers();
        Status = failures > 0 ? $"Bento off · {failures} windows could not be restored; their snapshots were kept."
            : restorePositions ? "Windows restored · activate Bento again to resume" : "Bento off · session layout kept in place";
        trayInterface.Refresh();
    }
    internal bool SaveSettingsOnShutdown(BentoSettings settings)
    {
        if (!disposed || !settings.IsValid) return false;
        try { settings.Save(); Settings = settings; pendingSettings = null; return true; }
        catch (Exception ex) { Status = ex.Message; return false; }
    }
    public bool UpdateSettings(BentoSettings settings)
    {
        if (disposed) return false;
        if (!settings.IsValid) { Report("Please check the settings values."); return false; }
        if (Dragging || activeNativeDrag != 0) { pendingSettings = settings; Status = "Settings will apply after dragging."; return true; }
        var old = Settings;
        foreach (var state in sessions.All.Append(session).Distinct()) state.WorkAreas.Clear();
        resizeHandles.Clear();
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
            if (EnsureDesktop() && automatic && !Paused) { Validate(history.Current); Apply(history.Current, history.Current); }
            UpdateLeases();
            settings.Save(); AppTheme.Apply(settings.Theme); RefreshDesktopDividers(); return true;
        }
        catch (Exception ex)
        {
            Settings = old;
            try { UpdateLeases(); } catch { }
            try { if (EnsureDesktop() && automatic && !Paused) Apply(history.Current, history.Current); } catch { /* Preserve the original failure report. */ }
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
        if (preview is null || nativeResizeWindow != 0) { dropPreview.Hide(); return; }
        if (divider is not null && dividerMonitor is not null)
        {
            dropPreview.Hide();
            var monitor = monitors.Single(m => m.Id == dividerMonitor);
            var boundary = Layout(monitor, preview).Dividers.Single(d => d.SplitId == divider.SplitId);
            dividers.FirstOrDefault(h => h.SplitId == dividerSurface)?.PresentResize(boundary.Bounds);
            if (preview.Roots[monitor.Id] is { } root) UpdateJoinCue(monitor, root, boundary);
            return;
        }
        if (incoming is null) { dropPreview.Hide(); return; }
        IEnumerable<PreviewSlot> Slots(WorkspaceState state) => monitors.SelectMany(m => Layout(m, state).Regions
            .Select(region => new PreviewSlot(region.Window.WindowId, m.Id, region.Bounds)));
        var slots = LayoutPreview.ForDrag(Slots(history.Current), Slots(preview), incoming.WindowId);
        dropPreview.Present(slots, monitors, incoming.WindowId, Settings.Animate && SystemParameters.ClientAreaAnimation);
    }
    private IReadOnlyList<ResizeHandle> Handles(DesktopMonitor monitor, WorkspaceState state) =>
        state.Roots.GetValueOrDefault(monitor.Id) is { } root ? resizeHandles.Get(monitor.Id, root, Area(monitor), Gap(monitor)) : [];
    private void RefreshDesktopDividers()
    {
        if (disposed || Dragging) return;
        RefreshBackdrops();
        try
        {
            resizeHandles.Retain(monitors.Select(m => m.Id).ToHashSet());
            var wanted = automatic && !Paused && HelpersAllowed ? monitors.SelectMany(m =>
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
                handle.SuppressInkForJoin(joinCues.OfType<JoinedSeamCue>().Any(cue => cue.Bounds == boundary.Bounds));
            }
            PlaceDividersBelowInterface(); RefreshPausedShades();
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
        if (!HelpersAllowed) { CloseBackdrops(); return; }
        var occupied = automatic ? monitors.Where(m => history.Current.Roots.GetValueOrDefault(m.Id) is not null).ToArray() : [];
        foreach (string id in backdrops.Keys.Where(id => !occupied.Any(m => m.Id == id)).ToArray())
        { backdrops[id].Close(); backdrops.Remove(id); }
        var applications = Windows.Select(w => w.Id).ToList();
        if (appWindow?.IsVisible == true && appWindow.WindowState != WindowState.Minimized) applications.Add(new WindowInteropHelper(appWindow).Handle.ToInt64());
        applications.AddRange(dividers.Where(w => w.IsVisible).Select(w => new WindowInteropHelper(w).Handle.ToInt64()));
        applications.AddRange(joinCues.Where(w => w.IsVisible).Select(w => new WindowInteropHelper(w).Handle.ToInt64()));
        foreach (var monitor in occupied)
        {
            if (!backdrops.TryGetValue(monitor.Id, out var backdrop)) backdrops[monitor.Id] = backdrop = new();
            backdrop.Present(monitor, Settings.BackgroundDarkness, applications);
        }
    }
    public void QuitKeepingWindows() { Dispose(); Application.Current.Shutdown(); }
    public void Dispose()
    {
        if (disposed) return;
        disposed = true; automatic = false;
        void Cleanup(Action action) { try { action(); } catch (Exception ex) { Status = ex.Message; } }
        // Invalidate callbacks before any WPF Closing handler or capture loss.
        // Each cleanup is independent; a disconnected shell or failed recovery
        // write must not leave input hooks/timers alive or make Quit abort.
        Cleanup(() => { timer.Stop(); platformTimer.Stop(); membershipTimer.Stop(); geometryTimer.Stop(); CancelSettled(); });
        Cleanup(() => { pointer?.Dispose(); pointer = null; });
        Cleanup(ClosePausedShades); Cleanup(CloseJoinCues); Cleanup(CloseOrganizing); Cleanup(CloseWaiting);
        Cleanup(() => appWindow?.FlushSettingsForShutdown());
        if (pendingSettings is { } settings) { SaveSettingsOnShutdown(settings); pendingSettings = null; }
        Cleanup(() => ClearDrag(restoreLive: false));
        activeNativeDrag = 0; nativeStartBounds = null; completingNativeGesture = 0;
        resizeHandles.Clear(); workAreaBaseline.Clear(); savedSession = null; lastBento = null;
        Microsoft.Win32.SystemEvents.UserPreferenceChanged -= AppearanceChanged;
        Cleanup(WallpaperContrast.Invalidate); Cleanup(events.Dispose); Cleanup(() => transition?.Dispose());
        Cleanup(CloseDesktopHelpers); Cleanup(() => appWindow?.Close()); Cleanup(CloseBackdrops);
        sessions.Clear(); Cleanup(() => desktopEnvironment?.Dispose());
        Cleanup(() => taskbarLease?.Dispose()); Cleanup(() => snapLease?.Dispose()); // Failed leases retain their recovery journal.
        Cleanup(() => DesktopIntegration.UnregisterShortcut(source.Handle, 1)); Cleanup(source.Dispose); Cleanup(trayInterface.Dispose);
    }
}
