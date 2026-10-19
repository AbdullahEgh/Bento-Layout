namespace Bento.Core;

public sealed record SessionWindow(long Id, uint ProcessId, PixelSize Minimum);

// No path/title matching and no disk serialization: HWND reuse or a new process
// cannot inherit a previous application's slot. Ordinary settings are independent.
public sealed class SessionLayoutSnapshot
{
    private readonly WorkspaceState state;
    private readonly IReadOnlyDictionary<long, uint> owners;
    public SessionLayoutSnapshot(WorkspaceState state, IEnumerable<SessionWindow> windows)
    {
        this.state = state;
        owners = windows.ToDictionary(w => w.Id, w => w.ProcessId);
    }
    private SessionLayoutSnapshot(WorkspaceState state, IReadOnlyDictionary<long, uint> owners)
    { this.state = state; this.owners = owners; }
    public bool Contains(long window) => owners.ContainsKey(window) && state.Windows.Any(w => w.WindowId == window);
    public SessionLayoutSnapshot Without(long window) => new(state.Remove(window), owners.Where(e => e.Key != window).ToDictionary(e => e.Key, e => e.Value));
    public WorkspaceState Reconcile(IEnumerable<SessionWindow> windows, IEnumerable<string> displays)
    {
        var live = windows.ToDictionary(w => w.Id);
        var result = state;
        foreach (var leaf in state.Windows)
        {
            if (!live.TryGetValue(leaf.WindowId, out var window) || !owners.TryGetValue(leaf.WindowId, out var owner) || owner != window.ProcessId)
                result = result.Remove(leaf.WindowId);
            else
                foreach (var entry in result.Roots.Where(e => e.Value is not null).ToArray())
                    result = result.WithRoot(entry.Key, LayoutEngine.Replace(entry.Value!, leaf.Id, leaf with { Minimum = window.Minimum }));
        }
        var available = displays.ToHashSet();
        return new WorkspaceState(result.Roots.Where(e => available.Contains(e.Key)));
    }
}
