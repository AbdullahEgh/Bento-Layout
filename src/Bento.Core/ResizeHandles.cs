using System.Security.Cryptography;
using System.Text;

namespace Bento.Core;

// Each seam carries an equivalent tree. Choose it once on pointer down; geometry
// stays identical until the gesture actually moves that seam.
public sealed record ResizeHandle(Divider Divider, LayoutNode Root, bool Shared = false);

public static class ResizeHandles
{
    public static IReadOnlyList<ResizeHandle> Calculate(LayoutNode root, PixelRect area, int gap)
    {
        var original = LayoutEngine.Calculate(root, area, gap);
        var result = original.Dividers.Select(d => new ResizeHandle(d, root)).ToList();
        if (gap == 0) return MovableHandles();
        var visited = new HashSet<PixelRect>();
        Visit(root, area, root);
        return MovableHandles();

        int[] Cuts(IReadOnlyList<Region> regions, SplitAxis axis) => regions
            .Select(r => axis == SplitAxis.Horizontal ? r.Bounds.Right : r.Bounds.Bottom).Distinct().Order()
            .Where(cut =>
            {
                bool h = axis == SplitAxis.Horizontal;
                var a = regions.Where(r => (h ? r.Bounds.Right : r.Bounds.Bottom) <= cut).ToArray();
                var b = regions.Where(r => (h ? r.Bounds.X : r.Bounds.Y) >= cut + gap).ToArray();
                return a.Length > 0 && b.Length > 0 && a.Length + b.Length == regions.Count
                    && b.Any(r => (h ? r.Bounds.X : r.Bounds.Y) == cut + gap);
            }).ToArray();

        LayoutNode? Build(IReadOnlyList<Region> regions, PixelRect rect, SplitAxis preferred,
            (SplitAxis Axis, int Cut)? forced = null)
        {
            if (regions.Count == 1) return regions[0].Bounds == rect ? regions[0].Window : null;
            IEnumerable<(SplitAxis Axis, int Cut)> choices = forced is { } choice ? new[] { choice }
                : new[] { preferred, preferred == SplitAxis.Horizontal ? SplitAxis.Vertical : SplitAxis.Horizontal }
                    .SelectMany(axis => Cuts(regions, axis).Select(cut => (axis, cut)));
            foreach (var (axis, cut) in choices)
            {
                bool h = axis == SplitAxis.Horizontal;
                var a = regions.Where(r => (h ? r.Bounds.Right : r.Bounds.Bottom) <= cut).ToArray();
                var b = regions.Where(r => (h ? r.Bounds.X : r.Bounds.Y) >= cut + gap).ToArray();
                if (a.Length == 0 || b.Length == 0 || a.Length + b.Length != regions.Count) continue;
                int start = h ? rect.X : rect.Y, length = (h ? rect.Width : rect.Height) - gap;
                if (length <= 0) continue;
                PixelRect first = h ? new PixelRect(rect.X, rect.Y, cut - start, rect.Height) : new(rect.X, rect.Y, rect.Width, cut - start);
                PixelRect second = h ? new PixelRect(cut + gap, rect.Y, rect.Right - cut - gap, rect.Height)
                    : new(rect.X, cut + gap, rect.Width, rect.Bottom - cut - gap);
                var left = Build(a, first, preferred); var right = Build(b, second, preferred);
                if (left is null || right is null) continue;
                PixelRect bounds = h ? new PixelRect(cut, rect.Y, gap, rect.Height) : new(rect.X, cut, rect.Width, gap);
                var id = original.Dividers.FirstOrDefault(d => d.Axis == axis && d.Bounds == bounds && d.ParentBounds == rect)?.SplitId
                    ?? StableId(regions, axis, a);
                return new SplitNode(id, axis, (cut - start) / (double)length, left, right);
            }
            return null;
        }

        void Visit(LayoutNode node, PixelRect rect, LayoutNode baseline)
        {
            var layout = LayoutEngine.Calculate(node, rect, gap);
            if (visited.Add(rect))
                foreach (var axis in new[] { SplitAxis.Horizontal, SplitAxis.Vertical })
                    foreach (int cut in Cuts(layout.Regions, axis))
                    {
                        var alternate = Build(layout.Regions, rect, axis, (axis, cut));
                        if (alternate is null) continue;
                        var candidate = LayoutEngine.Replace(baseline, node.Id, alternate);
                        var geometry = LayoutEngine.Calculate(candidate, area, gap);
                        if (geometry.Regions.Count != original.Regions.Count || geometry.Regions.Any(r =>
                            !original.Regions.Any(o => o.Window.WindowId == r.Window.WindowId && o.Bounds == r.Bounds))) continue;
                        foreach (var d in geometry.Dividers)
                            if (!result.Any(r => r.Divider.Axis == d.Axis && r.Divider.Bounds == d.Bounds && r.Divider.ParentBounds == d.ParentBounds))
                                result.Add(new(d, candidate));
                        // Rotated children can expose a partial three-column group.
                        Visit(alternate, rect, candidate);
                    }
            if (node is not SplitNode split) return;
            var seam = layout.Dividers[0].Bounds;
            bool h = split.Axis == SplitAxis.Horizontal;
            Visit(split.First, h ? new(rect.X, rect.Y, seam.X - rect.X, rect.Height) : new(rect.X, rect.Y, rect.Width, seam.Y - rect.Y), baseline);
            Visit(split.Second, h ? new(seam.Right, rect.Y, rect.Right - seam.Right, rect.Height) : new(rect.X, seam.Bottom, rect.Width, rect.Bottom - seam.Bottom), baseline);
        }

        IReadOnlyList<ResizeHandle> MovableHandles()
        {
            result.RemoveAll(handle => !Movable(handle.Root, handle.Divider));
            return result.Select(handle => handle with { Shared = result.Any(other => Contains(handle, other)) }).ToArray();
        }
        bool Movable(LayoutNode node, Divider divider)
        {
            if (node is not SplitNode s) return false;
            if (s.Id != divider.SplitId) return Movable(s.First, divider) || Movable(s.Second, divider);
            var a = LayoutEngine.Minimum(s.First, gap); var b = LayoutEngine.Minimum(s.Second, gap);
            return s.Axis == SplitAxis.Horizontal ? a.Width + b.Width + gap < divider.ParentBounds.Width
                : a.Height + b.Height + gap < divider.ParentBounds.Height;
        }
    }

    private static Guid StableId(IReadOnlyList<Region> regions, SplitAxis axis, IReadOnlyList<Region> first)
    {
        string key = axis + string.Join(",", regions.Select(r => r.Window.Id).Order()) + ":" + string.Join(",", first.Select(r => r.Window.Id).Order());
        return new Guid(SHA256.HashData(Encoding.UTF8.GetBytes(key)).AsSpan(0, 16));
    }
    public static bool Contains(ResizeHandle outer, ResizeHandle inner)
    {
        var a = outer.Divider; var b = inner.Divider;
        return a.Axis == b.Axis && (a.Axis == SplitAxis.Horizontal
            ? a.Bounds.X == b.Bounds.X && a.Bounds.Y <= b.Bounds.Y && a.Bounds.Bottom >= b.Bounds.Bottom && a.Bounds.Height > b.Bounds.Height
            : a.Bounds.Y == b.Bounds.Y && a.Bounds.X <= b.Bounds.X && a.Bounds.Right >= b.Bounds.Right && a.Bounds.Width > b.Bounds.Width);
    }
    public static bool IsUniversal(ResizeHandle handle, IReadOnlyList<ResizeHandle> handles) => !handles.Any(h => Contains(h, handle));
    public static ResizeHandle? Hit(IReadOnlyList<ResizeHandle> handles, PixelPoint point, double scale = 1)
    {
        int Distance(ResizeHandle h) => Math.Abs(h.Divider.Axis == SplitAxis.Horizontal
            ? point.Y - (h.Divider.Bounds.Y + h.Divider.Bounds.Height / 2)
            : point.X - (h.Divider.Bounds.X + h.Divider.Bounds.Width / 2));
        var hits = handles.Where(h => h.Divider.Bounds.Contains(point)).ToArray();
        var local = hits.Where(h => !IsUniversal(h, handles) && Distance(h) <= 80 * scale).ToArray();
        return (local.Length > 0 ? local : hits.Where(h => IsUniversal(h, handles)))
            .OrderBy(Distance).ThenBy(h => (long)h.Divider.Bounds.Width + h.Divider.Bounds.Height).ThenBy(h => h.Divider.SplitId).FirstOrDefault();
    }
}

public sealed class ResizeHandleCache
{
    private sealed record Entry(LayoutNode Root, PixelRect Area, int Gap, IReadOnlyList<ResizeHandle> Handles);
    private readonly Dictionary<string, Entry> entries = new();
    public int CalculationCount { get; private set; }
    public int EntryCount => entries.Count;
    public IReadOnlyList<ResizeHandle> Get(string display, LayoutNode root, PixelRect area, int gap)
    {
        if (entries.TryGetValue(display, out var e) && e.Root == root && e.Area == area && e.Gap == gap) return e.Handles;
        var handles = ResizeHandles.Calculate(root, area, gap);
        entries[display] = new(root, area, gap, handles); CalculationCount++;
        return handles;
    }
    public void Retain(IReadOnlySet<string> displays)
    {
        foreach (var key in entries.Keys.Where(k => !displays.Contains(k)).ToArray()) entries.Remove(key);
    }
    public void Clear() => entries.Clear();
}
