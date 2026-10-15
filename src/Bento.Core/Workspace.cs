using System.Collections.ObjectModel;

namespace Bento.Core;

// Immutable snapshots make preview, cancellation and undo independent of native HWND mutations.
public sealed class WorkspaceState
{
    public IReadOnlyDictionary<string, LayoutNode?> Roots { get; }
    public WorkspaceState(IEnumerable<KeyValuePair<string, LayoutNode?>>? roots = null) =>
        Roots = new ReadOnlyDictionary<string, LayoutNode?>(roots?.ToDictionary() ?? new());
    public IEnumerable<WindowNode> Windows => Roots.Values.SelectMany(LayoutEngine.Windows);
    public WorkspaceState WithRoot(string monitor, LayoutNode? root)
    {
        var next = Roots.ToDictionary();
        next[monitor] = root;
        return new(next);
    }
    public WorkspaceState Remove(long windowId) => new(Roots.Select(kv =>
        new KeyValuePair<string, LayoutNode?>(kv.Key, LayoutEngine.Remove(kv.Value, windowId))));

    public WorkspaceState Place(string monitor, Guid? targetId, WindowNode incoming, Placement placement)
    {
        Roots.TryGetValue(monitor, out var originalRoot);
        var target = LayoutEngine.Windows(originalRoot).FirstOrDefault(w => w.Id == targetId);
        if (targetId is null && originalRoot is not null)
            throw new ArgumentException("Choose a region in the occupied monitor.", nameof(targetId));
        if (target?.WindowId == incoming.WindowId) return this;
        if (targetId.HasValue && target is null) throw new ArgumentException("The target no longer exists.", nameof(targetId));
        var source = Windows.FirstOrDefault(w => w.WindowId == incoming.WindowId);
        var state = Remove(incoming.WindowId);
        state.Roots.TryGetValue(monitor, out var root);
        if (target is null) return state.WithRoot(monitor, incoming);
        if (placement == Placement.Center)
        {
            // A managed window swaps; an unassigned window replaces (the displaced window floats).
            if (source is not null)
            {
                state = this;
                foreach (var entry in Roots)
                {
                    if (entry.Value is null) continue;
                    var swapped = LayoutEngine.Replace(entry.Value, source.Id, target with { Id = source.Id });
                    swapped = LayoutEngine.Replace(swapped, target.Id, incoming with { Id = target.Id });
                    state = state.WithRoot(entry.Key, swapped);
                }
                return state;
            }
            return state.WithRoot(monitor, LayoutEngine.Replace(root!, target.Id, incoming));
        }
        bool horizontal = placement is Placement.Left or Placement.Right;
        bool before = placement is Placement.Left or Placement.Top;
        var split = new SplitNode(Guid.NewGuid(), horizontal ? SplitAxis.Horizontal : SplitAxis.Vertical,
            .5, before ? incoming : target, before ? target : incoming);
        return state.WithRoot(monitor, LayoutEngine.Replace(root!, target.Id, split));
    }
}

public sealed class LayoutHistory
{
    private readonly Stack<WorkspaceState> undo = new();
    private readonly Stack<WorkspaceState> redo = new();
    public WorkspaceState Current { get; private set; } = new();
    public bool CanUndo => undo.Count > 0;
    public void Commit(WorkspaceState next)
    {
        if (ReferenceEquals(next, Current)) return;
        undo.Push(Current);
        if (undo.Count > 100)
        {
            var retained = undo.Take(100).Reverse().ToArray();
            undo.Clear();
            foreach (var state in retained) undo.Push(state);
        }
        Current = next;
        redo.Clear();
    }
    public WorkspaceState Undo()
    {
        if (undo.TryPop(out var previous)) { redo.Push(Current); Current = previous; }
        return Current;
    }
    public WorkspaceState Redo()
    {
        if (redo.TryPop(out var next)) { undo.Push(Current); Current = next; }
        return Current;
    }
}
