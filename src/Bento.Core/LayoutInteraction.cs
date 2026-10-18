namespace Bento.Core;

public static class LayoutInteraction
{
    // Move only the sliding seam; accept a join only when minima allow exact alignment.
    public static LayoutNode SnapSeam(LayoutNode root, Guid id, PixelRect area, int gap, int distance = 12)
    {
        var layout = LayoutEngine.Calculate(root, area, gap);
        var moving = layout.Dividers.FirstOrDefault(d => d.SplitId == id);
        if (moving is null) return root;
        bool h = moving.Axis == SplitAxis.Horizontal;
        int position = h ? moving.Bounds.X : moving.Bounds.Y;
        var neighbors = layout.Dividers.Where(d => d.SplitId != id && d.Axis == moving.Axis &&
            (h ? Math.Abs(d.Bounds.Bottom - moving.Bounds.Y) <= gap || Math.Abs(moving.Bounds.Bottom - d.Bounds.Y) <= gap
                : Math.Abs(d.Bounds.Right - moving.Bounds.X) <= gap || Math.Abs(moving.Bounds.Right - d.Bounds.X) <= gap))
            .Where(d => Math.Abs((h ? d.Bounds.X : d.Bounds.Y) - position) <= distance)
            .OrderBy(d => Math.Abs((h ? d.Bounds.X : d.Bounds.Y) - position)).ThenBy(d => h ? d.Bounds.X : d.Bounds.Y);
        foreach (var neighbor in neighbors)
        {
            int target = h ? neighbor.Bounds.X : neighbor.Bounds.Y;
            int length = (h ? moving.ParentBounds.Width : moving.ParentBounds.Height) - gap;
            if (length <= 0) continue;
            var candidate = LayoutEngine.Resize(root, id, (target - (h ? moving.ParentBounds.X : moving.ParentBounds.Y)) / (double)length);
            var actual = LayoutEngine.Calculate(candidate, area, gap).Dividers.Single(d => d.SplitId == id);
            if ((h ? actual.Bounds.X : actual.Bounds.Y) == target) return candidate;
        }
        return root;
    }

    public static LayoutNode ResizeWindow(LayoutNode root, long id, PixelRect requested, PixelRect area, int gap, int snapDistance = 12)
    {
        var before = LayoutEngine.Calculate(root, area, gap).Regions.FirstOrDefault(r => r.Window.WindowId == id);
        if (before is null) return root;
        var result = root;
        var edits = new[] { (SplitAxis.Horizontal, true, requested.X - before.Bounds.X),
            (SplitAxis.Horizontal, false, requested.Right - before.Bounds.Right),
            (SplitAxis.Vertical, true, requested.Y - before.Bounds.Y),
            (SplitAxis.Vertical, false, requested.Bottom - before.Bounds.Bottom) };
        foreach (var (axis, leading, delta) in edits.Where(e => Math.Abs(e.Item3) > 2))
        {
            bool h = axis == SplitAxis.Horizontal;
            var leaf = LayoutEngine.Calculate(result, area, gap).Regions.Single(r => r.Window.WindowId == id);
            int edge = h ? leading ? leaf.Bounds.X : leaf.Bounds.Right : leading ? leaf.Bounds.Y : leaf.Bounds.Bottom;
            var local = ResizeHandles.Calculate(result, area, gap).Where(handle =>
            {
                var d = handle.Divider;
                int boundary = h ? leading ? d.Bounds.Right : d.Bounds.X : leading ? d.Bounds.Bottom : d.Bounds.Y;
                bool covers = h ? d.ParentBounds.Y <= leaf.Bounds.Y && d.ParentBounds.Bottom >= leaf.Bounds.Bottom
                    : d.ParentBounds.X <= leaf.Bounds.X && d.ParentBounds.Right >= leaf.Bounds.Right;
                return d.Axis == axis && edge == boundary && covers;
            }).OrderBy(handle => (long)handle.Divider.ParentBounds.Width * handle.Divider.ParentBounds.Height).FirstOrDefault();
            if (local is null) continue;
            var seam = local.Divider;
            int length = (h ? seam.ParentBounds.Width : seam.ParentBounds.Height) - gap;
            if (length <= 0) continue;
            int offset = (h ? seam.Bounds.X - seam.ParentBounds.X : seam.Bounds.Y - seam.ParentBounds.Y) + delta;
            result = SnapSeam(LayoutEngine.Resize(local.Root, seam.SplitId, offset / (double)length), seam.SplitId, area, gap, snapDistance);
        }
        return result;
    }

    public static Placement? ScreenEdge(PixelRect screen, PixelPoint point, int distance)
    {
        if (!screen.Contains(point)) return null;
        var nearest = new[] { (Placement.Left, point.X - screen.X), (Placement.Right, screen.Right - 1 - point.X),
            (Placement.Top, point.Y - screen.Y), (Placement.Bottom, screen.Bottom - 1 - point.Y) }.OrderBy(p => p.Item2).First();
        return nearest.Item2 < distance ? nearest.Item1 : null;
    }

    // Carry the entire outermost eligible section instead of squeezing one leaf
    // into another section's slot. Use measured geometry when ratios were clamped.
    public static LayoutNode? MoveSection(LayoutNode root, long window, Placement edge, PixelRect area, int gap)
    {
        if (edge == Placement.Center || !LayoutEngine.Windows(root).Any(w => w.WindowId == window)) return null;
        var layout = LayoutEngine.Calculate(root, area, gap);
        var axis = edge is Placement.Left or Placement.Right ? SplitAxis.Horizontal : SplitAxis.Vertical;
        bool wantsFirst = edge is Placement.Left or Placement.Top;
        LayoutNode? Move(LayoutNode node)
        {
            if (node is not SplitNode split) return null;
            bool inFirst = LayoutEngine.Windows(split.First).Any(w => w.WindowId == window);
            if (split.Axis == axis && inFirst != wantsFirst)
            {
                var d = layout.Dividers.Single(d => d.SplitId == split.Id);
                int length = (axis == SplitAxis.Horizontal ? d.ParentBounds.Width : d.ParentBounds.Height) - gap;
                int offset = axis == SplitAxis.Horizontal ? d.Bounds.X - d.ParentBounds.X : d.Bounds.Y - d.ParentBounds.Y;
                return split with { Ratio = (length - offset) / (double)length, First = split.Second, Second = split.First };
            }
            var child = Move(inFirst ? split.First : split.Second);
            return child is null ? null : split with { First = inFirst ? child : split.First, Second = inFirst ? split.Second : child };
        }
        var moved = Move(root);
        if (moved is not null) LayoutEngine.Calculate(moved, area, gap);
        return moved;
    }
}
