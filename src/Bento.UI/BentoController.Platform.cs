using System.Windows.Interop;
using System.Windows.Threading;

namespace Bento.UI;

public sealed partial class BentoController
{
    private sealed class DesktopSession
    {
        public readonly LayoutHistory History = new();
        public readonly Dictionary<long, WindowSnapshot> Originals = new();
        public readonly Dictionary<long, (AppWindow Window, WindowSnapshot Snapshot)> Minimized = new();
        public readonly HashSet<long> Reopened = new(), Released = new(), ResumeHeld = new(), Fullscreen = new();
        public readonly Dictionary<long, long> Interactions = new();
        public readonly Dictionary<long, uint> OverflowBeforeOff = new();
        public readonly Dictionary<long, (PixelRect Slot, bool Caption)> AppliedFrames = new();
        public readonly Dictionary<string, (LayoutNode Root, PixelRect Area, int Gap)> WorkAreas = new();
        public readonly PauseState Pause = new();
        public IReadOnlyList<AppWindow> Windows = [];
        public IReadOnlyList<DesktopMonitor> Monitors = [];
        public readonly Dictionary<long, AppWindow> FullscreenKnown = new();
        public SessionLayoutSnapshot? Remembered, Saved, FullscreenReference;
        public bool Active, HideTaskbar, NeedsReapply;
        public long LastActive;
        public string? FailedMembership;
    }
    private readonly DesktopSessions<DesktopSession> sessions = new(() => new());
    private DesktopSession session => sessions.Current;
    private readonly IDesktopEnvironment? desktopEnvironment;
    private readonly TaskbarLease? taskbarLease;
    private readonly Dictionary<long, PausedWindowShade> pausedShades = new();
    private PointerObserver? pointer;
    private readonly DispatcherTimer platformTimer = new() { Interval = TimeSpan.FromMilliseconds(250) };
    private readonly DispatcherTimer membershipTimer = new() { Interval = TimeSpan.FromMilliseconds(80) };
    private readonly DispatcherTimer geometryTimer = new() { Interval = TimeSpan.FromMilliseconds(100) };
    private readonly DispatcherTimer settledTimer = new() { Interval = TimeSpan.FromMilliseconds(180) };
    private bool environmentSuspended, overview, fullscreenForeground, changingDesktop;
    private bool? pendingPause, pendingTaskbar;
    private BentoSettings? pendingSettings;
    public bool Interacting => Dragging || activeNativeDrag != 0;
    private long nativeRevision, settledRevision, geometryStarted, geometryStableSince;
    private WorkspaceState? settledState;
    private bool settledLearnMinimum;
    private IReadOnlyList<DesktopMonitor>? pendingGeometry;
    private IReadOnlyList<ResizeHandle>? gestureHandles;
    private LayoutNode? gestureHandlesRoot;
    private readonly List<Window> joinCues = new();
    public bool Suspended => environmentSuspended || overview;
    public bool Paused => session.Pause.Paused;
    public bool HideTaskbar => session.HideTaskbar;
    public bool HelpersAllowed => !disposed && !changingDesktop && !environmentSuspended && !overview && !fullscreenForeground;

    private void ConfigurePlatformTimers()
    {
        membershipTimer.Tick += (_, _) => { membershipTimer.Stop(); RefreshMembership(); };
        platformTimer.Tick += (_, _) =>
        {
            if (!EnsureDesktop()) return;
            platformTimer.Interval = TimeSpan.FromMilliseconds(automatic || sessions.All.Any(s => s.Active) ? 250 : 1000);
            if (!automatic) return;
            RefreshFullscreenReservations();
            if (session.HideTaskbar && taskbarLease?.Superseded == true) { session.HideTaskbar = false; UpdateLeases(); RequestGeometryRefresh(); trayInterface.Refresh(); }
            if (Paused) RefreshPausedShades();
        };
        if (desktopEnvironment is not null) platformTimer.Start();
        geometryTimer.Tick += (_, _) =>
        {
            if (!EnsureDesktop() || Dragging || activeNativeDrag != 0) return;
            var latest = WindowCatalog.Monitors(); long now = clock();
            if (pendingGeometry is null || !pendingGeometry.SequenceEqual(latest)) { pendingGeometry = latest; geometryStableSince = now; }
            if (now - geometryStarted < 300 || now - geometryStableSince < 250)
            {
                if (now - geometryStarted > 3000) { geometryTimer.Stop(); Report("Waiting for the Windows work area to settle."); }
                return;
            }
            geometryTimer.Stop(); RefreshMonitorGeometry();
        };
        settledTimer.Tick += (_, _) =>
        {
            settledTimer.Stop();
            if (disposed || !automatic || settledRevision != nativeRevision || settledState is null || !ReferenceEquals(history.Current, settledState) ||
                Dragging || activeNativeDrag != 0 || Paused || !EnsureDesktop()) return;
            // One bounded same-tree repair, never a recursive arrangement or an
            // unbounded chase of an application's delayed native animation.
            foreach (var monitor in monitors)
                foreach (var region in Layout(monitor, settledState).Regions)
                    try
                    {
                        // User minimization after commit supersedes its delayed
                        // repair. Never restore that window from a timer.
                        if (WindowCatalog.IsMinimized(region.Window.WindowId)) { RequestMembershipRefresh(); continue; }
                        if (CanWriteNative(region.Window.WindowId) && !native.Accepts(region.Window.WindowId, region.Bounds)) native.Move(region.Window.WindowId, region.Bounds, learnMinimum: settledLearnMinimum);
                    }
                    catch (Exception ex) { Report(ex.Message); }
        };
    }
    private bool EnsureDesktop()
    {
        if (disposed) return false;
        if (desktopEnvironment is null) return !overview;
        var sample = desktopEnvironment.Sample();
        if (sample.Suspended || sample.Desktop is not { } desktop || desktop == Guid.Empty || overview)
        {
            if (!environmentSuspended)
            {
                environmentSuspended = true; session.NeedsReapply |= automatic; sessions.Invalidate(); CancelSettled();
                transition?.Dispose(); transition = null; geometryTimer.Stop(); membershipTimer.Stop();
                ClearDrag(restoreLive: false); activeNativeDrag = 0; nativeStartBounds = null;
                CloseDesktopHelpers(); CloseBackdrops(); ClosePausedShades(); CloseJoinCues(); pointer?.Dispose(); pointer = null;
                // Restore owned shell preferences while the active desktop is
                // unknown. Fullscreen detection itself does not take this path.
                UpdateLeases(); trayInterface.Refresh();
            }
            Status = sample.Reason ?? "Desktop transition: arrangement deferred.";
            return false;
        }
        if (changingDesktop) return sessions.Desktop == desktop;
        bool switched = sessions.Desktop != desktop, resumed = environmentSuspended;
        environmentSuspended = false;
        if (switched)
        {
            changingDesktop = true;
            try
            {
                session.NeedsReapply |= automatic;
                transition?.Dispose(); transition = null; geometryTimer.Stop(); membershipTimer.Stop();
                CancelSettled(); ClearDrag(restoreLive: false); activeNativeDrag = 0; nativeStartBounds = null;
                CloseDesktopHelpers(); CloseBackdrops(); ClosePausedShades(); CloseJoinCues(); pointer?.Dispose(); pointer = null;
                pendingPause = null; pendingTaskbar = null; resizeHandles.Clear();
                sessions.Switch(desktop); fullscreenForeground = false;
                UpdateLeases();
                if (automatic) { Windows = DiscoverWindows(useCache: false); RefreshDesktopDividers(); }
                trayInterface.Refresh();
            }
            finally { changingDesktop = false; }
        }
        if ((resumed || switched) && automatic) { UpdateLeases(); RefreshDesktopDividers(); RequestMembershipRefresh(); }
        if (resumed || switched) trayInterface.Refresh();
        if ((resumed || switched) && pendingSettings is not null) Dispatch(ApplyPendingInteractionState, scoped: false);
        return true;
    }
    private bool CanWriteNative(long id) => IdentityMatches(id) && !disposed && !changingDesktop && !environmentSuspended && !overview && WindowCatalog.IsVisible(id) && !WindowCatalog.IsCloaked(id) &&
        (desktopEnvironment is null || sessions.Desktop is { } desktop && desktopEnvironment.IsCurrent(desktop) &&
            desktopEnvironment.Contains(desktop, id) && !LooksFullscreen(id));
    private bool LooksFullscreen(long id)
    {
        if (id == completingNativeGesture || desktopEnvironment is null || !WindowCatalog.Exists(id) || WindowCatalog.IsMinimized(id) || WindowCatalog.IsMaximized(id)) return false;
        var screen = WindowCatalog.ScreenBounds(id);
        if (screen is null) return desktopEnvironment.Fullscreen(id);
        try
        {
            var actual = native.VisibleBounds(id);
            bool caption = WindowCatalog.HasCaption(id);
            if (session.AppliedFrames.TryGetValue(id, out var applied) && applied.Caption == caption && NativeFrameFit.Accepts(actual, applied.Slot)) return false;
            return desktopEnvironment.Fullscreen(id) || FullscreenGeometry.Reserve(actual, screen.Value, false, caption,
                session.AppliedFrames.TryGetValue(id, out applied) ? applied.Slot : null, session.AppliedFrames.TryGetValue(id, out applied) ? applied.Caption : null);
        }
        catch (InvalidOperationException) { return true; } // Unknown presentation: decline a write.
    }
    private bool IdentityMatches(long id)
    {
        uint actual = WindowCatalog.ProcessId(id);
        uint? expected = Windows.FirstOrDefault(w => w.Id == id)?.ProcessId;
        if (expected is null && originals.TryGetValue(id, out var original)) expected = original.ProcessId;
        if (expected is null && minimizedByBento.TryGetValue(id, out var minimized)) expected = minimized.Snapshot.ProcessId;
        return expected is { } owner && owner == actual;
    }
    private void ForgetWindow(long id)
    {
        bool known = false;
        foreach (var state in sessions.All.Append(session).Distinct())
        {
            if (!state.History.Current.Windows.Any(w => w.WindowId == id) && !state.Originals.ContainsKey(id) &&
                !state.Minimized.ContainsKey(id) && !state.Released.Contains(id) && !state.Windows.Any(w => w.Id == id) && state.Saved?.Contains(id) != true && state.Remembered?.Contains(id) != true) continue;
            known = true; state.NeedsReapply |= state.Active && state.History.Current.Windows.Any(w => w.WindowId == id); state.History.Forget(id); state.Originals.Remove(id); state.Minimized.Remove(id);
            state.Reopened.Remove(id); state.Released.Remove(id); state.ResumeHeld.Remove(id); state.Interactions.Remove(id);
            state.Saved = state.Saved?.Without(id); state.Remembered = state.Remembered?.Without(id); state.FullscreenReference = state.FullscreenReference?.Without(id);
            state.Fullscreen.Remove(id); state.FullscreenKnown.Remove(id); state.OverflowBeforeOff.Remove(id); state.AppliedFrames.Remove(id);
            if (state.Fullscreen.Count == 0) state.FullscreenReference = null; state.WorkAreas.Clear(); state.FailedMembership = null;
            state.Windows = state.Windows.Where(w => w.Id != id).ToArray();
            state.Pause.Retain(state.Pause.Members.Where(member => member != id).ToHashSet());
        }
        if (!known) return;
        native.ForgetWindow(id); CancelSettled();
        dropProposals.Clear(); dragIntent.Reset(); preview = null; previewDestination = null; validPreview = false; dropPreview?.Hide();
        if (incoming?.WindowId == id || nativeResizeWindow == id || activeNativeDrag == id)
        { ClearDrag(restoreLive: false); activeNativeDrag = 0; nativeStartBounds = null; }
        else if (divider is not null || nativeResizeWindow != 0)
        { ClearDrag(restoreLive: false); CloseJoinCues(); }
        RequestMembershipRefresh();
    }
    private bool CurrentMember(long id) => desktopEnvironment is null || sessions.Desktop is { } desktop && desktopEnvironment.Contains(desktop, id);
    private void CancelSettled() { nativeRevision++; settledTimer.Stop(); settledState = null; }
    private void ScheduleSettled()
    {
        if (disposed || Paused || !automatic) return;
        settledState = history.Current; settledRevision = nativeRevision; settledLearnMinimum = !reflowing && workAreaBaseline.Count == 0; settledTimer.Stop(); settledTimer.Start();
    }
    private void RequestMembershipRefresh()
    { if (!disposed && !membershipTimer.IsEnabled) membershipTimer.Start(); }
    private void RefreshMembership()
    {
        if (!EnsureDesktop()) return;
        Windows = DiscoverWindows(); RememberActiveWindow(); RefreshFullscreenReservations();
        if (Paused) RefreshPausedShades();
        else if (automatic && !Interacting) { ReapplyCurrentSession(); Synchronize(); }
        PlaceDividersBelowInterface();
    }
    private void RequestGeometryRefresh()
    {
        if (disposed) return;
        geometryStarted = clock(); geometryStableSince = geometryStarted; pendingGeometry = null;
        geometryTimer.Stop(); geometryTimer.Start();
    }
    private void UpdateLeases()
    {
        bool owns = automatic && !environmentSuspended && !overview;
        try { snapLease?.SetSuppressed(owns && Settings.SuppressWindowsSnap); }
        catch (Exception ex) { Report(ex.Message); }
        try { taskbarLease?.SetHidden(owns && session.HideTaskbar); }
        catch (Exception ex) { session.HideTaskbar = false; Report(ex.Message); }
    }
    public void SetTaskbarHidden(bool hidden)
    {
        if (!EnsureDesktop()) return;
        if (Dragging || activeNativeDrag != 0) { pendingTaskbar = hidden; return; }
        if (hidden && !automatic) ArrangeDesktop();
        if (hidden && !automatic) return;
        session.HideTaskbar = hidden; UpdateLeases(); RequestGeometryRefresh(); trayInterface.Refresh();
    }
    public void CheckDesktopContext() => EnsureDesktop();
    public void TrayHold() { if (EnsureDesktop() && automatic) SetTaskbarHidden(!HideTaskbar); }
    public void StopArrangingSelectedWindow() { if (EnsureDesktop() && lastActiveWindow != 0) Remove(lastActiveWindow); }
    public int OutsideCount => Windows.Count(w => !history.Current.Windows.Any(leaf => leaf.WindowId == w.Id) && !WindowCatalog.IsMinimized(w.Id));
    public void TogglePause() { if (EnsureDesktop()) SetPaused(!Paused); }
    public void ToggleTaskbar() { if (EnsureDesktop()) SetTaskbarHidden(!HideTaskbar); }
    public void TrayClick() { if (!EnsureDesktop()) return; if (Paused) SetPaused(false); else ToggleBento(); }
    public void SetPaused(bool pause)
    {
        if (!EnsureDesktop()) return;
        if (Dragging || activeNativeDrag != 0) { pendingPause = pause; return; }
        if (pause && !automatic) ArrangeDesktop();
        if (!automatic || Paused == pause) return;
        CancelSettled();
        if (pause)
        {
            if (!history.Current.Windows.Any()) { Report("Open a supported window before pausing Bento."); return; }
            session.Pause.Enter(history.Current.Windows.Select(w => w.WindowId), lastActiveWindow != 0 ? lastActiveWindow : WindowCatalog.Foreground);
        }
        else
        {
            var current = DiscoverWindows(useCache: false); Windows = current;
            var members = session.Pause.Members.ToHashSet();
            var candidates = current.Where(w => !members.Contains(w.Id) && !WindowCatalog.IsMinimized(w.Id) && CanWriteNative(w.Id)).Select(w => w.Id).ToHashSet();
            var above = DesktopIntegration.AboveMembers(candidates, members);
            foreach (var window in current.Where(w => above.Contains(w.Id)))
            {
                try { var snapshot = native.Capture(window.Id); native.Minimize(window.Id); if (WindowCatalog.IsMinimized(window.Id)) { minimizedByBento[window.Id] = (window, snapshot); session.ResumeHeld.Add(window.Id); } }
                catch (Exception ex) { Report(ex.Message); }
            }
            Windows = DiscoverWindows(useCache: false);
            try
            {
                bool previousReflow = reflowing; reflowing |= workAreaBaseline.Count > 0;
                try { if (!Commit(ReflowCurrentAreas(history.Current), restoreRemoved: false)) { RefreshPausedShades(); return; } }
                finally { reflowing = previousReflow; }
            }
            catch (LayoutConstraintException ex) { Report(ex.Message); RefreshPausedShades(); return; }
            session.Pause.Exit(); session.NeedsReapply = false; ClosePausedShades();
            Synchronize(); ScheduleSettled();
        }
        UpdatePausePointer(); RefreshDesktopDividers(); trayInterface.Refresh();
    }
    private void OnForeground()
    {
        if (!EnsureDesktop()) return;
        long foreground = WindowCatalog.Foreground;
        if (WindowCatalog.ProcessId(foreground) != Environment.ProcessId || appWindow is not null && new WindowInteropHelper(appWindow).Handle.ToInt64() == foreground)
            session.Pause.Focus(foreground);
        RefreshFullscreenReservations();
        RememberActiveWindow(); PlaceDividersBelowInterface(); RefreshPausedShades();
    }
    private void UpdatePausePointer()
    {
        if (!Paused || !HelpersAllowed) { pointer?.Dispose(); pointer = null; return; }
        if (pointer is not null) return;
        try
        {
            pointer = new PointerObserver();
            pointer.Pressed += point => Dispatch(() =>
            {
                if (!Paused || !EnsureDesktop() || !HelpersAllowed) return;
                var ignored = Application.Current.Windows.Cast<Window>().Where(w => w is PausedWindowShade or DesktopBackdropWindow or DesktopDividerWindow or DropPreviewWindow or PreviewDimWindow or TransitionWindow or JoinedSeamCue)
                    .Select(w => new WindowInteropHelper(w).Handle.ToInt64()).ToHashSet();
                long member = DesktopIntegration.ApplicationAt(point, session.Pause.Members, ignored);
                if (member == 0) return;
                session.Pause.Focus(member, clicked: true); RefreshPausedShades();
            });
        }
        catch (Exception ex) { Report(ex.Message); }
    }
    private void RefreshPausedShades()
    {
        if (!Paused || !HelpersAllowed) { ClosePausedShades(); UpdatePausePointer(); return; }
        var wanted = Windows.Where(w => session.Pause.Dimmed(w.Id) && CurrentMember(w.Id) && WindowCatalog.IsVisible(w.Id) &&
            !WindowCatalog.IsMinimized(w.Id) && !LooksFullscreen(w.Id)).ToArray();
        foreach (long id in pausedShades.Keys.Where(id => !wanted.Any(w => w.Id == id)).ToArray()) { pausedShades[id].Close(); pausedShades.Remove(id); }
        foreach (var window in wanted)
        {
            try
            {
                if (!pausedShades.TryGetValue(window.Id, out var shade)) pausedShades[window.Id] = shade = new();
                shade.Present(window.Id, native.VisibleBounds(window.Id), window.DpiScale);
            }
            catch (Exception ex) { Report(ex.Message); }
        }
        UpdatePausePointer();
    }
    private void ClosePausedShades() { foreach (var shade in pausedShades.Values) shade.Close(); pausedShades.Clear(); }
    private void CloseJoinCues() { foreach (var cue in joinCues.ToArray()) cue.Close(); joinCues.Clear(); }
    private WorkspaceState ReflowCurrentAreas(WorkspaceState state)
    {
        foreach (var entry in state.Roots.ToArray())
            if (entry.Value is { } original)
            {
                var root = original;
                foreach (var leaf in LayoutEngine.Windows(root).ToArray())
                    if (Windows.FirstOrDefault(w => w.Id == leaf.WindowId) is { } window) root = LayoutEngine.Replace(root, leaf.Id, leaf with { Minimum = window.Minimum });
                state = state.WithRoot(entry.Key, root);
            }
        foreach (var monitor in monitors)
            if (state.Roots.GetValueOrDefault(monitor.Id) is { } root && workAreaBaseline.TryGetValue(monitor.Id, out var reference))
                state = state.WithRoot(monitor.Id, LayoutReflow.PreservingSeams(root, reference.Root, reference.Area, Area(monitor), Gap(monitor), reference.Gap));
        return state;
    }
    private void ReapplyCurrentSession()
    {
        if (!session.NeedsReapply || !automatic || Paused || Interacting) return;
        session.NeedsReapply = false; monitors = WindowCatalog.Monitors();
        try { Commit(ReflowCurrentAreas(history.Current), restoreRemoved: false); }
        catch (LayoutConstraintException ex) { Report(ex.Message); }
    }
    private SessionLayoutSnapshot CaptureSessionLayout()
    {
        if (session.FullscreenReference is not { } reference) return new(history.Current, SessionWindows);
        var state = reference.Reconcile(SessionWindows, monitors.Select(m => m.Id));
        foreach (var monitor in monitors)
        {
            var windows = Windows.Where(w => !released.Contains(w.Id) && !session.ResumeHeld.Contains(w.Id) &&
                (string.IsNullOrEmpty(w.MonitorId) ? monitors.FirstOrDefault()?.Id : w.MonitorId) == monitor.Id)
                .Select(w => WindowNode.Create(w.Id, w.Minimum)).ToArray();
            state = state.WithRoot(monitor.Id, AutoLayout.Fitting(windows, Area(monitor), Gap(monitor), state.Roots.GetValueOrDefault(monitor.Id)));
        }
        return new(state, SessionWindows);
    }
    private WorkspaceState ReconcileReservedLayout(SessionLayoutSnapshot reference)
    {
        var state = reference.Reconcile(SessionWindows, monitors.Select(m => m.Id));
        foreach (var monitor in monitors)
        {
            var candidates = Windows.Where(w => !released.Contains(w.Id) && !session.ResumeHeld.Contains(w.Id) && !session.Fullscreen.Contains(w.Id) &&
                (string.IsNullOrEmpty(w.MonitorId) ? monitors.FirstOrDefault()?.Id : w.MonitorId) == monitor.Id)
                .OrderByDescending(w => lastInteraction.GetValueOrDefault(w.Id)).Select(w => WindowNode.Create(w.Id, w.Minimum)).ToArray();
            state = state.WithRoot(monitor.Id, AutoLayout.Fitting(candidates, Area(monitor), Gap(monitor), state.Roots.GetValueOrDefault(monitor.Id)));
        }
        return state;
    }
    private void ApplyPendingInteractionState()
    {
        if (disposed || Dragging || activeNativeDrag != 0) return;
        if (pendingSettings is { } settings) { pendingSettings = null; UpdateSettings(settings); }
        if (pendingTaskbar is { } hidden) { pendingTaskbar = null; SetTaskbarHidden(hidden); }
        if (pendingPause is { } pause) { pendingPause = null; SetPaused(pause); }
    }
    private void RefreshFullscreenReservations()
    {
        if (!automatic || desktopEnvironment is null || changingDesktop || Dragging || activeNativeDrag != 0) return;
        bool wasForeground = fullscreenForeground;
        fullscreenForeground = LooksFullscreen(WindowCatalog.Foreground);
        var previous = session.Fullscreen.ToHashSet();
        var next = Windows.Concat(session.FullscreenKnown.Values).DistinctBy(w => w.Id)
            .Where(w => CurrentMember(w.Id) && WindowCatalog.Exists(w.Id) && LooksFullscreen(w.Id)).Select(w => w.Id).ToHashSet();
        // Reserve only members; a floating fullscreen app suppresses helpers but
        // cannot acquire an unrelated member's slot.
        next.IntersectWith(history.Current.Windows.Select(w => w.WindowId).Concat(previous));
        if (!previous.SetEquals(next))
        {
            CancelSettled();
            if (previous.Count == 0 && next.Count > 0) session.FullscreenReference = new(history.Current, SessionWindows);
            foreach (var window in Windows.Where(w => next.Contains(w.Id))) session.FullscreenKnown[window.Id] = window;
            session.Fullscreen.Clear(); session.Fullscreen.UnionWith(next);
            var state = history.Current;
            foreach (long id in next) state = state.Remove(id);
            if (next.Count == 0 && session.FullscreenReference is { } reference)
            {
                Windows = DiscoverWindows(useCache: false);
                state = ReconcileReservedLayout(reference);
                session.FullscreenReference = null; session.FullscreenKnown.Clear();
            }
            if (Paused) history.Commit(state);
            else if (Commit(state, restoreRemoved: false)) Synchronize();
        }
        if (wasForeground != fullscreenForeground) { failedMembership = null; RefreshDesktopDividers(); RequestMembershipRefresh(); }
        RefreshPausedShades();
    }
    private void UpdateJoinCue(DesktopMonitor monitor, LayoutNode root, Divider moving)
    {
        if (!HelpersAllowed || !Settings.Animate || !SystemParameters.ClientAreaAnimation || root == gestureHandlesRoot) return;
        var handles = resizeHandles.Get(monitor.Id, root, Area(monitor), Gap(monitor));
        var joined = ResizeHandles.NewlyJoinedSection(handles, gestureHandles ?? [], moving);
        gestureHandles = handles; gestureHandlesRoot = root;
        if (joined is null)
        {
            if (joinCues.OfType<JoinedSeamCue>().Any(cue => !handles.Any(h => h.Shared && h.Divider.Bounds == cue.Bounds))) CloseJoinCues();
            return;
        }
        CloseJoinCues();
        var cue = new JoinedSeamCue(joined, handles, monitor, Settings.BackgroundDarkness);
        joinCues.Add(cue); cue.Closed += (_, _) =>
        {
            joinCues.Remove(cue);
            foreach (var handle in dividers.Where(h => h.DesktopBounds == cue.Bounds)) handle.SuppressInkForJoin(false);
        }; cue.Show();
        foreach (var handle in dividers.Where(h => h.DesktopBounds == cue.Bounds)) handle.SuppressInkForJoin(true);
        var applications = Windows.Select(w => w.Id).ToList();
        if (appWindow?.IsVisible == true) applications.Add(new WindowInteropHelper(appWindow).Handle.ToInt64());
        DesktopIntegration.PlaceBehindApplications(new WindowInteropHelper(cue).Handle, applications); RefreshBackdrops();
    }
    private void UpdateNativeJoinCue(DesktopMonitor monitor, LayoutNode root, long window, PixelRect requested)
    {
        var before = Layout(monitor, dragStart).Regions.FirstOrDefault(r => r.Window.WindowId == window);
        var after = LayoutEngine.Calculate(root, Area(monitor), Gap(monitor)).Regions.FirstOrDefault(r => r.Window.WindowId == window);
        if (before is null || after is null) return;
        var edits = new[] { (SplitAxis.Horizontal, true, Math.Abs(requested.X - before.Bounds.X)),
            (SplitAxis.Horizontal, false, Math.Abs(requested.Right - before.Bounds.Right)),
            (SplitAxis.Vertical, true, Math.Abs(requested.Y - before.Bounds.Y)),
            (SplitAxis.Vertical, false, Math.Abs(requested.Bottom - before.Bounds.Bottom)) };
        foreach (var (axis, leading, delta) in edits.Where(e => e.Item3 > 2).OrderByDescending(e => e.Item3))
        {
            bool h = axis == SplitAxis.Horizontal;
            int edge = h ? leading ? after.Bounds.X : after.Bounds.Right : leading ? after.Bounds.Y : after.Bounds.Bottom;
            var moving = resizeHandles.Get(monitor.Id, root, Area(monitor), Gap(monitor)).Where(handle =>
            {
                var d = handle.Divider;
                return d.Axis == axis && edge == (h ? leading ? d.Bounds.Right : d.Bounds.X : leading ? d.Bounds.Bottom : d.Bounds.Y) &&
                    (h ? d.ParentBounds.Y <= after.Bounds.Y && d.ParentBounds.Bottom >= after.Bounds.Bottom : d.ParentBounds.X <= after.Bounds.X && d.ParentBounds.Right >= after.Bounds.Right);
            }).OrderBy(handle => (long)handle.Divider.ParentBounds.Width * handle.Divider.ParentBounds.Height).FirstOrDefault();
            if (moving is null) continue;
            UpdateJoinCue(monitor, root, moving.Divider); break;
        }
    }
    private WorkspaceState AlignNativeSeams(WorkspaceState state, DesktopSession owner)
    {
        if (reflowing || Paused || session.Fullscreen.Count > 0) return state;
        Dictionary<long, PixelRect> frames;
        try { frames = state.Windows.Where(w => WindowCatalog.Exists(w.WindowId)).ToDictionary(w => w.WindowId, w => native.VisibleBounds(w.WindowId)); }
        catch (InvalidOperationException ex) { Status = ex.Message; return state; }
        var candidate = state; long oldScore = 0;
        foreach (var monitor in monitors)
            if (state.Roots.GetValueOrDefault(monitor.Id) is { } root)
            {
                long score = NativeSeamAlignment.Score(root, Area(monitor), Gap(monitor), frames);
                if (score == long.MaxValue) return state;
                oldScore += score;
                if (NativeSeamAlignment.Propose(root, Area(monitor), Gap(monitor), frames) is { } proposed) candidate = candidate.WithRoot(monitor.Id, proposed);
            }
        if (ReferenceEquals(candidate, state)) return state;
        try
        {
            Apply(state, candidate, restoreRemoved: false, animate: false, expectedOwner: owner);
            var after = candidate.Windows.ToDictionary(w => w.WindowId, w => native.VisibleBounds(w.WindowId)); long score = 0;
            foreach (var monitor in monitors)
                if (candidate.Roots.GetValueOrDefault(monitor.Id) is { } root)
                { long value = NativeSeamAlignment.Score(root, Area(monitor), Gap(monitor), after); if (value == long.MaxValue) throw new LayoutConstraintException("Native seam did not improve."); score += value; }
            if (score < oldScore) return candidate;
        }
        catch (Exception ex) { Status = ex.Message; }
        if (!ReferenceEquals(owner, session)) throw new InvalidOperationException("Desktop changed during seam validation.");
        try { Apply(candidate, state, restoreRemoved: false, animate: false, expectedOwner: owner); }
        catch (Exception ex) when (ex is InvalidOperationException or LayoutConstraintException or System.ComponentModel.Win32Exception)
        { Status = ex.Message; } // Settled verification makes at most one further same-tree repair.
        return state;
    }
}
