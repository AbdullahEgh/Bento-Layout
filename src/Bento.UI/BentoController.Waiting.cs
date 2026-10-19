namespace Bento.UI;

public sealed partial class BentoController
{
    private WaitingWindow? waitingWindow;
    private string? waitingMembership, dismissedWaiting;
    private long waitingIncoming;
    private readonly Dictionary<long, List<PixelRect>> refusedWaiting = new();
    public int WaitingCount => minimizedByBento.Keys.Count(id => !session.ResumeHeld.Contains(id) && CurrentMember(id));
    private void CloseWaiting() { waitingWindow?.Close(); waitingWindow = null; waitingMembership = null; }
    public void DismissWaiting() { dismissedWaiting = waitingMembership; CloseWaiting(); }
    private void RefreshWaiting()
    {
        if (disposed || !automatic || Paused || organizing || !HelpersAllowed) { CloseWaiting(); return; }
        if (Dragging || windowSource is not null) return;
        var windows = minimizedByBento.Values.Select(e => e.Window).Where(w => !session.ResumeHeld.Contains(w.Id) && CurrentMember(w.Id) && WindowCatalog.IsMinimized(w.Id)).ToArray();
        string membership = string.Join(",", windows.Select(w => w.Id).Order());
        if (windows.Length == 0) { CloseWaiting(); dismissedWaiting = null; return; }
        if (waitingMembership == membership || dismissedWaiting == membership) return;
        CloseWaiting();
        if (monitors.FirstOrDefault() is not { } monitor) return;
        waitingMembership = membership;
        waitingWindow = new WaitingWindow(this, monitor, windows); waitingWindow.Show();
    }
    public bool BeginWaitingDrag(long id)
    {
        if (!EnsureDesktop() || !automatic || Paused || !minimizedByBento.ContainsKey(id)) return false;
        BeginDrag(id); waitingIncoming = id; UpdatePreview(); return Dragging;
    }
    public void EndWaitingDrag() { waitingIncoming = 0; CloseWaiting(); RefreshWaiting(); }
    private bool CommitWaiting(WorkspaceState next, long id)
    {
        if (!minimizedByBento.TryGetValue(id, out var source)) return false;
        var before = history.Current;
        var removed = before.Windows.Where(w => !next.Windows.Any(n => n.WindowId == w.WindowId)).Select(w => w.WindowId).ToArray();
        var displaced = new List<(AppWindow Window, WindowSnapshot Snapshot)>();
        try
        {
            foreach (long other in removed)
            {
                var window = Windows.Single(w => w.Id == other);
                displaced.Add((window, native.Capture(other)));
                native.Minimize(other);
                if (!WindowCatalog.IsMinimized(other)) throw new InvalidOperationException("The occupied window could not be minimized.");
            }
            if (!Commit(next, restoreRemoved: false)) throw new InvalidOperationException(Status);
            minimizedByBento.Remove(id); refusedWaiting.Remove(id);
            foreach (var entry in displaced) minimizedByBento[entry.Window.Id] = entry;
            return true;
        }
        catch (Exception ex)
        {
            foreach (var entry in displaced) { try { native.Restore(entry.Snapshot); } catch { } }
            try { native.Minimize(id); } catch { }
            minimizedByBento[id] = source;
            var slot = monitors.SelectMany(m => Layout(m, next).Regions).FirstOrDefault(r => r.Window.WindowId == id)?.Bounds;
            if (slot is { } bounds) { if (!refusedWaiting.TryGetValue(id, out var list)) refusedWaiting[id] = list = new(); list.Add(bounds); }
            Status = ex.Message; return false;
        }
    }
}
