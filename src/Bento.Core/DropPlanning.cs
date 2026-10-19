namespace Bento.Core;

public static class DropPlanning
{
    // Try the requested placement first. Equivalent trees preserve every existing
    // cell but can expose usable space hidden by an unrelated ancestor split.
    public static WorkspaceState Place(WorkspaceState state, string monitor, Guid? target, WindowNode incoming,
        Placement placement, IReadOnlyDictionary<string, PixelRect> areas, IReadOnlyDictionary<string, int> gaps, bool otherAxis = false)
    {
        var bases = new List<WorkspaceState> { state };
        var directions = new List<Placement> { placement };
        if (otherAxis) directions.Add(placement == Placement.Right ? Placement.Bottom : Placement.Right);
        bool expanded = false;
        foreach (var direction in directions)
        {
            for (int index = 0; index < bases.Count; index++)
            {
                var next = bases[index].Place(monitor, target, incoming, direction);
                try
                {
                    foreach (var entry in next.Roots)
                        if (entry.Value is not null) LayoutEngine.Calculate(entry.Value, areas[entry.Key], gaps[entry.Key]);
                    return next;
                }
                catch (LayoutConstraintException)
                {
                    if (!expanded && state.Roots.GetValueOrDefault(monitor) is { } root)
                    {
                        expanded = true;
                        foreach (var alternate in ResizeHandles.Calculate(root, areas[monitor], gaps[monitor]).Select(h => h.Root).Distinct())
                            if (alternate != root) bases.Add(state.WithRoot(monitor, alternate));
                    }
                }
            }
        }
        throw new LayoutConstraintException("This destination cannot fit these windows.");
    }
}
