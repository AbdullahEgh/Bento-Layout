namespace Bento.Core;

/// <summary>Builds an adaptive split tree for every supplied window, without a fixed row/column grid.</summary>
public static class AutoLayout
{
    public static LayoutNode? Fitting(IReadOnlyList<WindowNode> windows, PixelRect area, int gap = 8,
        LayoutNode? previous = null, IReadOnlySet<long>? priority = null, IReadOnlyList<long>? leastRecentlyUsed = null)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(gap);
        if (area.Width < 0 || area.Height < 0 || windows.Any(w => w.Minimum.Width <= 0 || w.Minimum.Height <= 0))
            throw new ArgumentException("Window minima and available area must be valid.");
        if (windows.Select(w => w.WindowId).Distinct().Count() != windows.Count)
            throw new ArgumentException("A window can appear only once.");
        var ids = windows.Select(w => w.WindowId).ToHashSet();
        foreach (var leaf in LayoutEngine.Windows(previous).ToArray())
            previous = ids.Contains(leaf.WindowId)
                ? LayoutEngine.Replace(previous!, leaf.Id, leaf with { Minimum = windows.First(w => w.WindowId == leaf.WindowId).Minimum })
                : LayoutEngine.Remove(previous, leaf.WindowId);
        try { LayoutEngine.Calculate(previous, area, gap); }
        catch (LayoutConstraintException) { previous = null; }
        var feasible = windows.Where(w => w.Minimum.Width <= area.Width && w.Minimum.Height <= area.Height).ToArray();
        if (feasible.Length == 0) return null;
        var admission = feasible.Where(w => priority?.Contains(w.WindowId) == true).Select(w => w.WindowId).ToHashSet();
        var candidates = feasible.OrderByDescending(w => admission.Contains(w.WindowId)).ToList();
        var oldest = (leastRecentlyUsed ?? []).Select((id, index) => (id, index)).ToDictionary(p => p.id, p => p.index);
        var eviction = candidates.Where(w => !admission.Contains(w.WindowId)).OrderBy(w => oldest.GetValueOrDefault(w.WindowId, -1)).Select(w => w.WindowId).ToArray();
        for (int attempt = 0; ; attempt++)
        {
            // When one admitted app fits exactly in one evicted idle slot,
            // retain that slot and every unrelated custom split.
            if (attempt > 0 && previous is not null)
            {
                var leaves = LayoutEngine.Windows(previous).ToArray();
                var removed = leaves.Where(w => !candidates.Any(c => c.WindowId == w.WindowId)).ToArray();
                var incoming = candidates.Where(w => !leaves.Any(old => old.WindowId == w.WindowId)).ToArray();
                if (removed.Length == 1 && incoming.Length == 1)
                {
                    var replacement = LayoutEngine.Replace(previous, removed[0].Id, incoming[0] with { Id = removed[0].Id });
                    try { LayoutEngine.Calculate(replacement, area, gap); return replacement; }
                    catch (LayoutConstraintException) { }
                }
            }
            if (previous is null && CapacityPlanner.Plan(candidates, area, gap) is { } initial) return initial;
            LayoutNode? retained = previous;
            foreach (var leaf in LayoutEngine.Windows(retained).Where(w => !candidates.Any(c => c.WindowId == w.WindowId)).ToArray())
                retained = LayoutEngine.Remove(retained, leaf.WindowId);
            try
            {
                foreach (var window in candidates) retained = Insert(retained, window, area, gap);
                if (LayoutEngine.Windows(retained).Count() == candidates.Count) return retained;
            }
            catch (LayoutConstraintException) { }
            var planned = CapacityPlanner.Plan(candidates, area, gap);
            if (planned is not null) return planned;
            if (admission.Count == 0)
            {
                // Unchanged overflow is not a new admission request. Retain the
                // valid edited tree (plus any feasible local insertions) instead
                // of generating a new subset/tree on every membership sample.
                if (previous is not null && retained is not null) return retained;
                planned = CapacityPlanner.Plan(candidates, area, gap, all: false);
                if (planned is not null) return planned;
            }
            if (attempt >= eviction.Length) break;
            candidates.RemoveAll(w => w.WindowId == eviction[attempt]);
        }
        // Multiple priority apps may themselves exceed capacity. Keep the most
        // recent feasible subset; an impossible app never evicts usable members.
        return CapacityPlanner.Plan(candidates, area, gap, all: false)
            ?? (candidates.Count > 0 ? candidates[0] : null);
    }

    public static LayoutNode? Arrange(IReadOnlyList<WindowNode> windows, PixelRect area, int gap = 8)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(gap);
        if (windows.Select(w => w.WindowId).Distinct().Count() != windows.Count)
            throw new ArgumentException("A window can appear only once.", nameof(windows));
        if (windows.Count == 0) return null;
        var failed = new HashSet<(int, int, int, int)>();
        int remaining = 100_000;
        var result = Build(0, windows.Count, area.Width, area.Height);
        if (result is null) throw new LayoutConstraintException("All active windows cannot fit at their minimum sizes. Close or minimize a window, or use another monitor.");
        LayoutEngine.Calculate(result, area, gap);
        return result;

        LayoutNode? Build(int start, int count, int width, int height)
        {
            if (--remaining < 0 || width <= 0 || height <= 0) return null;
            if (count == 1)
            {
                var window = windows[start];
                return width >= window.Minimum.Width && height >= window.Minimum.Height ? window : null;
            }
            var key = (start, count, width, height);
            if (failed.Contains(key)) return null;
            // Wider regions split left/right; taller regions stack. Odd counts naturally produce a larger tile.
            bool wide = width >= height * 1.35;
            foreach (bool horizontal in new[] { wide, !wide })
            foreach (int firstCount in Enumerable.Range(1, count - 1).OrderBy(n => Math.Abs(n - count / 2d)).ThenBy(n => n))
            {
                int length = (horizontal ? width : height) - gap;
                int minFirst = windows.Skip(start).Take(firstCount).Max(w => horizontal ? w.Minimum.Width : w.Minimum.Height);
                int minSecond = windows.Skip(start + firstCount).Take(count - firstCount).Max(w => horizontal ? w.Minimum.Width : w.Minimum.Height);
                if (length < minFirst + minSecond) continue;
                var cuts = new[] { length / 2, (int)Math.Round(length * firstCount / (double)count), minFirst, length - minSecond }
                    .Select(cut => Math.Clamp(cut, minFirst, length - minSecond)).Distinct();
                foreach (int cut in cuts)
                {
                    var a = Build(start, firstCount, horizontal ? cut : width, horizontal ? height : cut);
                    if (a is null) continue;
                    var b = Build(start + firstCount, count - firstCount, horizontal ? length - cut : width, horizontal ? height : length - cut);
                    if (b is not null) return new SplitNode(Guid.NewGuid(), horizontal ? SplitAxis.Horizontal : SplitAxis.Vertical,
                        cut / (double)length, a, b);
                }
            }
            failed.Add(key);
            return null;
        }
    }

    /// <summary>Insert without rebuilding a manually customized tree; use the largest feasible existing region.</summary>
    public static LayoutNode Insert(LayoutNode? root, WindowNode incoming, PixelRect area, int gap = 8)
    {
        if (root is null) return Arrange([incoming], area, gap)!;
        if (LayoutEngine.Windows(root).Any(w => w.WindowId == incoming.WindowId)) return root;
        foreach (var region in LayoutEngine.Calculate(root, area, gap).Regions.OrderByDescending(r => (long)r.Bounds.Width * r.Bounds.Height))
        {
            bool wide = region.Bounds.Width >= region.Bounds.Height * 1.35;
            foreach (bool horizontal in new[] { wide, !wide })
            {
                var branch = new SplitNode(Guid.NewGuid(), horizontal ? SplitAxis.Horizontal : SplitAxis.Vertical, .5, region.Window, incoming);
                var candidate = LayoutEngine.Replace(root, region.Window.Id, branch);
                try { LayoutEngine.Calculate(candidate, area, gap); return candidate; }
                catch (LayoutConstraintException) { }
            }
        }
        return Arrange(LayoutEngine.Windows(root).Append(incoming).ToArray(), area, gap)!;
    }
}
