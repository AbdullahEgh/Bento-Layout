namespace Bento.Core;

public abstract record LayoutNode(Guid Id);
public sealed record WindowNode(Guid Id, long WindowId, PixelSize Minimum) : LayoutNode(Id)
{
    public static WindowNode Create(long id, PixelSize minimum) => new(Guid.NewGuid(), id, minimum);
}
public sealed record SplitNode(Guid Id, SplitAxis Axis, double Ratio, LayoutNode First, LayoutNode Second) : LayoutNode(Id);
public sealed record Region(WindowNode Window, PixelRect Bounds);
public sealed record Divider(Guid SplitId, SplitAxis Axis, PixelRect Bounds, PixelRect ParentBounds);
public sealed record LayoutResult(IReadOnlyList<Region> Regions, IReadOnlyList<Divider> Dividers);
public sealed class LayoutConstraintException(string message) : Exception(message);

public static class LayoutEngine
{
    public static PixelSize Minimum(LayoutNode node, int gap) => node switch
    {
        WindowNode w => w.Minimum,
        SplitNode s when s.Axis == SplitAxis.Horizontal => new(
            Minimum(s.First, gap).Width + gap + Minimum(s.Second, gap).Width,
            Math.Max(Minimum(s.First, gap).Height, Minimum(s.Second, gap).Height)),
        SplitNode s => new(Math.Max(Minimum(s.First, gap).Width, Minimum(s.Second, gap).Width),
            Minimum(s.First, gap).Height + gap + Minimum(s.Second, gap).Height),
        _ => throw new ArgumentException("Unknown layout node.")
    };

    public static LayoutResult Calculate(LayoutNode? root, PixelRect bounds, int gap = 8)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(gap);
        var regions = new List<Region>();
        var dividers = new List<Divider>();
        if (root is not null) Visit(root, bounds);
        return new(regions, dividers);

        void Visit(LayoutNode node, PixelRect rect)
        {
            var minimum = Minimum(node, gap);
            if (rect.Width < minimum.Width || rect.Height < minimum.Height)
                throw new LayoutConstraintException("This region is too small for these windows. Choose a larger region.");
            if (node is WindowNode window) { regions.Add(new(window, rect)); return; }
            var split = (SplitNode)node;
            if (!double.IsFinite(split.Ratio)) throw new LayoutConstraintException("Invalid split ratio.");
            var firstMin = Minimum(split.First, gap);
            var secondMin = Minimum(split.Second, gap);
            bool horizontal = split.Axis == SplitAxis.Horizontal;
            int length = (horizontal ? rect.Width : rect.Height) - gap;
            int first = Math.Clamp((int)Math.Round(length * Math.Clamp(split.Ratio, 0, 1)),
                horizontal ? firstMin.Width : firstMin.Height,
                length - (horizontal ? secondMin.Width : secondMin.Height));
            PixelRect a = horizontal ? new(rect.X, rect.Y, first, rect.Height) : new(rect.X, rect.Y, rect.Width, first);
            PixelRect b = horizontal ? new(rect.X + first + gap, rect.Y, length - first, rect.Height)
                : new(rect.X, rect.Y + first + gap, rect.Width, length - first);
            PixelRect divider = horizontal ? new(rect.X + first, rect.Y, gap, rect.Height)
                : new(rect.X, rect.Y + first, rect.Width, gap);
            dividers.Add(new(split.Id, split.Axis, divider, rect));
            Visit(split.First, a);
            Visit(split.Second, b);
        }
    }

    public static IEnumerable<WindowNode> Windows(LayoutNode? node) => node switch
    {
        WindowNode window => [window],
        SplitNode split => Windows(split.First).Concat(Windows(split.Second)),
        _ => []
    };

    public static LayoutNode? Remove(LayoutNode? node, long windowId) => node switch
    {
        WindowNode w => w.WindowId == windowId ? null : w,
        SplitNode s => Collapse(s, Remove(s.First, windowId), Remove(s.Second, windowId)),
        _ => null
    };

    private static LayoutNode? Collapse(SplitNode s, LayoutNode? a, LayoutNode? b) =>
        a is null ? b : b is null ? a : s with { First = a, Second = b };

    public static LayoutNode Replace(LayoutNode node, Guid id, LayoutNode replacement) => node.Id == id ? replacement : node switch
    {
        SplitNode s => s with { First = Replace(s.First, id, replacement), Second = Replace(s.Second, id, replacement) },
        _ => node
    };

    public static LayoutNode Resize(LayoutNode node, Guid splitId, double ratio) => node switch
    {
        SplitNode s when s.Id == splitId => s with { Ratio = Math.Clamp(ratio, 0, 1) },
        SplitNode s => s with { First = Resize(s.First, splitId, ratio), Second = Resize(s.Second, splitId, ratio) },
        _ => node
    };

    // Anchor movement to the press location, including off-center and touch grabs.
    public static LayoutNode ResizeDivider(LayoutNode root, Divider divider, PixelPoint point, PixelPoint grabbedAt, int gap)
    {
        bool horizontal = divider.Axis == SplitAxis.Horizontal;
        int delta = horizontal ? point.X - grabbedAt.X : point.Y - grabbedAt.Y;
        if (delta == 0) return root;
        int position = (horizontal ? divider.Bounds.X - divider.ParentBounds.X : divider.Bounds.Y - divider.ParentBounds.Y) + delta;
        int length = (horizontal ? divider.ParentBounds.Width : divider.ParentBounds.Height) - gap;
        if (length <= 0) throw new LayoutConstraintException("This divider has no usable space.");
        return Resize(root, divider.SplitId, position / (double)length);
    }

    // Translate resizing a real window's inner edges into changes to its ancestor dividers.
    public static LayoutNode ResizeWindow(LayoutNode root, long windowId, PixelRect requested, PixelRect area, int gap = 8) =>
        LayoutInteraction.ResizeWindow(root, windowId, requested, area, gap);
}
