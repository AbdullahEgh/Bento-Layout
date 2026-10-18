namespace Bento.Core;

public static class LayoutReflow
{
    // Match coincident seams using a common feasible interval instead of letting
    // independent minimum clamps pull joined rows/columns apart.
    public static LayoutNode PreservingSeams(LayoutNode root, LayoutNode reference, PixelRect from, PixelRect to, int gap)
    {
        var original = LayoutEngine.Calculate(reference, from, gap);
        var result = root;
        var visited = new HashSet<Guid>();
        foreach (var seam in original.Dividers)
        {
            if (visited.Contains(seam.SplitId)) continue;
            bool h = seam.Axis == SplitAxis.Horizontal;
            int coordinate = h ? seam.Bounds.X : seam.Bounds.Y;
            var group = original.Dividers.Where(d => d.Axis == seam.Axis && (h ? d.Bounds.X : d.Bounds.Y) == coordinate).ToArray();
            visited.UnionWith(group.Select(d => d.SplitId));
            if (group.Length < 2) continue;
            var current = LayoutEngine.Calculate(result, to, gap);
            var dividers = current.Dividers.Where(d => group.Any(g => g.SplitId == d.SplitId)).ToArray();
            if (dividers.Length != group.Length) continue;
            int low = int.MinValue, high = int.MaxValue;
            foreach (var d in dividers)
            {
                var split = Find(result, d.SplitId)!;
                var a = LayoutEngine.Minimum(split.First, gap); var b = LayoutEngine.Minimum(split.Second, gap);
                low = Math.Max(low, h ? d.ParentBounds.X + a.Width : d.ParentBounds.Y + a.Height);
                high = Math.Min(high, (h ? d.ParentBounds.Right - b.Width : d.ParentBounds.Bottom - b.Height) - gap);
            }
            int oldLength = (h ? from.Width : from.Height) - gap;
            if (low > high || oldLength <= 0) continue;
            double fraction = (coordinate - (h ? from.X : from.Y)) / (double)oldLength;
            int target = Math.Clamp((h ? to.X : to.Y) + (int)Math.Round(fraction * ((h ? to.Width : to.Height) - gap)), low, high);
            foreach (var d in dividers)
            {
                int length = (h ? d.ParentBounds.Width : d.ParentBounds.Height) - gap;
                if (length > 0) result = LayoutEngine.Resize(result, d.SplitId, (target - (h ? d.ParentBounds.X : d.ParentBounds.Y)) / (double)length);
            }
        }
        LayoutEngine.Calculate(result, to, gap);
        return result;
    }
    private static SplitNode? Find(LayoutNode node, Guid id) => node is not SplitNode s ? null
        : s.Id == id ? s : Find(s.First, id) ?? Find(s.Second, id);
}
