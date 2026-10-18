using System.Numerics;

namespace Bento.Core;

// Bounded Pareto search: each subset keeps only non-dominated minimum rectangles.
// No native window probes; all geometry is checked before a membership change.
public static class CapacityPlanner
{
    private sealed record Shape(PixelSize Minimum, LayoutNode Tree);
    public static LayoutNode? Plan(IReadOnlyList<WindowNode> windows, PixelRect area, int gap, bool all = true)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(gap);
        if (windows.Select(w => w.WindowId).Distinct().Count() != windows.Count || windows.Any(w => w.Minimum.Width <= 0 || w.Minimum.Height <= 0))
            throw new ArgumentException("Window identities and minima must be valid.");
        if (windows.Count is 0 or > 8) return null;
        int end = 1 << windows.Count, remaining = 250_000;
        var shapes = Enumerable.Range(0, end).Select(_ => new List<Shape>()).ToArray();
        for (int i = 0; i < windows.Count; i++)
            if (windows[i].Minimum.Width <= area.Width && windows[i].Minimum.Height <= area.Height)
                shapes[1 << i].Add(new(windows[i].Minimum, windows[i]));
        for (int mask = 1; mask < end; mask++)
        {
            if (BitOperations.PopCount((uint)mask) < 2) continue;
            for (int a = (mask - 1) & mask; a > 0; a = (a - 1) & mask)
            {
                int b = mask ^ a;
                if ((a & (mask & -mask)) == 0) continue;
                foreach (var first in shapes[a]) foreach (var second in shapes[b])
                    foreach (var axis in new[] { SplitAxis.Horizontal, SplitAxis.Vertical })
                    {
                        if (--remaining < 0) return null;
                        var x = first.Minimum; var y = second.Minimum;
                        PixelSize minimum = axis == SplitAxis.Horizontal ? new PixelSize(x.Width + gap + y.Width, Math.Max(x.Height, y.Height))
                            : new(Math.Max(x.Width, y.Width), x.Height + gap + y.Height);
                        if (minimum.Width > area.Width || minimum.Height > area.Height ||
                            shapes[mask].Any(s => s.Minimum.Width <= minimum.Width && s.Minimum.Height <= minimum.Height)) continue;
                        shapes[mask].RemoveAll(s => minimum.Width <= s.Minimum.Width && minimum.Height <= s.Minimum.Height);
                        shapes[mask].Add(new(minimum, new SplitNode(Guid.NewGuid(), axis, .5, first.Tree, second.Tree)));
                    }
            }
        }
        IEnumerable<int> masks = all ? new[] { end - 1 } : Enumerable.Range(1, end - 1).Where(mask => (mask & 1) != 0)
            .OrderByDescending(mask => BitOperations.PopCount((uint)mask))
            .ThenByDescending(mask => Enumerable.Range(0, windows.Count).Sum(i => (mask & (1 << i)) != 0 ? 1 << (windows.Count - i) : 0));
        long primary = windows[0].WindowId;
        LayoutNode Expand(LayoutNode node, PixelRect bounds)
        {
            if (node is not SplitNode s) return node;
            bool h = s.Axis == SplitAxis.Horizontal;
            int length = (h ? bounds.Width : bounds.Height) - gap;
            double Weight(LayoutNode n) => LayoutEngine.Windows(n).Count() + (LayoutEngine.Windows(n).Any(w => w.WindowId == primary) ? .6 : 0);
            var a = LayoutEngine.Minimum(s.First, gap); var b = LayoutEngine.Minimum(s.Second, gap);
            int cut = Math.Clamp((int)Math.Round(length * Weight(s.First) / (Weight(s.First) + Weight(s.Second))),
                h ? a.Width : a.Height, length - (h ? b.Width : b.Height));
            PixelRect r1 = h ? new PixelRect(bounds.X, bounds.Y, cut, bounds.Height) : new(bounds.X, bounds.Y, bounds.Width, cut);
            PixelRect r2 = h ? new PixelRect(bounds.X + cut + gap, bounds.Y, length - cut, bounds.Height) : new(bounds.X, bounds.Y + cut + gap, bounds.Width, length - cut);
            return s with { Ratio = cut / (double)length, First = Expand(s.First, r1), Second = Expand(s.Second, r2) };
        }
        foreach (int mask in masks)
        {
            LayoutNode? best = null; double bestScore = double.NegativeInfinity;
            foreach (var shape in shapes[mask])
            {
                var tree = Expand(shape.Tree, area); var regions = LayoutEngine.Calculate(tree, area, gap).Regions;
                double primaryArea = regions.Where(r => r.Window.WindowId == primary).Sum(r => (double)r.Bounds.Width * r.Bounds.Height);
                double thinness = regions.Sum(r => Math.Max(0, Math.Abs(Math.Log(r.Bounds.Width / (double)r.Bounds.Height)) - 1.2));
                bool largest = regions.All(r => (double)r.Bounds.Width * r.Bounds.Height <= primaryArea);
                double score = primaryArea / Math.Max(1, (double)area.Width * area.Height) + (largest ? .25 : 0) - thinness * .15;
                if (score > bestScore) { best = tree; bestScore = score; }
            }
            if (best is not null) return best;
        }
        return null;
    }
}
