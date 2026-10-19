using Bento.Core;
using System.Text.Json;
using static Bento.Tests.Program;

namespace Bento.Tests;

internal static class ParityGeometryTests
{
    private static WindowNode W(long id, int width = 100, int height = 100) => WindowNode.Create(id, new(width, height));
    private static SplitNode S(SplitAxis axis, LayoutNode a, LayoutNode b, double ratio = .5) => new(Guid.NewGuid(), axis, ratio, a, b);
    private static LayoutNode Grid() => S(SplitAxis.Vertical, S(SplitAxis.Horizontal, W(1), W(2)), S(SplitAxis.Horizontal, W(3), W(4)));
    private static LayoutNode Transpose(LayoutNode node) => node is WindowNode w ? w with { Minimum = new(w.Minimum.Height, w.Minimum.Width) }
        : node is SplitNode s ? s with { Axis = s.Axis == SplitAxis.Horizontal ? SplitAxis.Vertical : SplitAxis.Horizontal, First = Transpose(s.First), Second = Transpose(s.Second) } : node;
    public static void RunAll()
    {
        foreach (bool transpose in new[] { false, true })
        {
            Run($"Equivalent grid exposes both local and group seams (transpose: {transpose})", () =>
            {
                var root = transpose ? Transpose(Grid()) : Grid(); var area = new PixelRect(-400, -100, 1008, 808);
                var handles = ResizeHandles.Calculate(root, area, 8);
                Equal(2, handles.Count(h => h.Shared));
                Equal(2, handles.Count(h => ResizeHandles.IsUniversal(h, handles)));
                foreach (var handle in handles)
                {
                    var original = LayoutEngine.Calculate(root, area, 8).Regions.OrderBy(r => r.Window.WindowId).ToArray();
                    var alternate = LayoutEngine.Calculate(handle.Root, area, 8).Regions.OrderBy(r => r.Window.WindowId).ToArray();
                    Check(original.SequenceEqual(alternate));
                }
            });
            Run($"Partial joined subgroup leaves third column unchanged (transpose: {transpose})", () =>
            {
                LayoutNode root = S(SplitAxis.Horizontal,
                    S(SplitAxis.Horizontal, S(SplitAxis.Vertical, W(1), W(2)), S(SplitAxis.Vertical, W(3), W(4))), W(5), .7);
                if (transpose) root = Transpose(root);
                var area = new PixelRect(0, 0, 1208, 1008);
                var handles = ResizeHandles.Calculate(root, area, 8);
                var axis = transpose ? SplitAxis.Horizontal : SplitAxis.Vertical;
                var group = handles.First(h => h.Shared && h.Divider.Axis == axis &&
                    (transpose ? h.Divider.Bounds.Height < area.Height : h.Divider.Bounds.Width < area.Width));
                var before = LayoutEngine.Calculate(root, area, 8).Regions.Single(r => r.Window.WindowId == 5).Bounds;
                var moved = LayoutEngine.Resize(group.Root, group.Divider.SplitId, .6);
                Equal(before, LayoutEngine.Calculate(moved, area, 8).Regions.Single(r => r.Window.WindowId == 5).Bounds);
            });
            Run($"Exact seam snap keeps stationary branch fixed (transpose: {transpose})", () =>
            {
                var first = S(SplitAxis.Horizontal, W(1), W(2), .5);
                var second = S(SplitAxis.Horizontal, W(3), W(4), .51);
                LayoutNode root = S(SplitAxis.Vertical, first, second);
                if (transpose) root = Transpose(root);
                var area = new PixelRect(0, 0, 1008, 1008);
                var before = LayoutEngine.Calculate(root, area, 8);
                var snapped = LayoutInteraction.SnapSeam(root, second.Id, area, 8);
                var after = LayoutEngine.Calculate(snapped, area, 8);
                var fixedSeam = before.Dividers.Single(d => d.SplitId == first.Id);
                var sliding = after.Dividers.Single(d => d.SplitId == second.Id);
                Equal(transpose ? fixedSeam.Bounds.Y : fixedSeam.Bounds.X, transpose ? sliding.Bounds.Y : sliding.Bounds.X);
                Equal(before.Regions.Single(r => r.Window.WindowId == 1).Bounds, after.Regions.Single(r => r.Window.WindowId == 1).Bounds);
            });
        }
        Run("Local grip hit range uses DIP scale; seam remainder chooses group", () =>
        {
            var area = new PixelRect(0, 0, 2008, 1608); var handles = ResizeHandles.Calculate(Grid(), area, 8);
            var local = handles.First(h => !ResizeHandles.IsUniversal(h, handles) && h.Divider.Axis == SplitAxis.Horizontal);
            var d = local.Divider;
            var point = new PixelPoint(d.Bounds.X + 2, d.Bounds.Y + d.Bounds.Height / 2 + 100);
            Check(ResizeHandles.Hit(handles, point, 1)!.Shared);
            Check(!ResizeHandles.Hit(handles, point, 2)!.Shared);
            Check(ResizeHandles.Hit(handles, new(-1, -1)) is null);
        });
        Run("Native border resize chooses equivalent local section", () =>
        {
            // Original tree is row-major. Editing the left column's horizontal
            // seam must not move the right column's coincident seam.
            var root = Grid(); var area = new PixelRect(0, 0, 1008, 808);
            var before = LayoutEngine.Calculate(root, area, 8).Regions;
            var leaf = before.Single(r => r.Window.WindowId == 1);
            var after = LayoutEngine.Calculate(LayoutEngine.ResizeWindow(root, 1, leaf.Bounds with { Height = leaf.Bounds.Height + 50 }, area, 8), area, 8).Regions;
            Equal(leaf.Bounds.Height + 50, after.Single(r => r.Window.WindowId == 1).Bounds.Height);
            foreach (long id in new long[] { 2, 4 }) Equal(before.Single(r => r.Window.WindowId == id).Bounds, after.Single(r => r.Window.WindowId == id).Bounds);
        });
        Run("Minimum clamp does not produce a false snap", () =>
        {
            var a = S(SplitAxis.Horizontal, W(1), W(2), .5);
            var b = S(SplitAxis.Horizontal, W(3, 506), W(4), .506);
            var root = S(SplitAxis.Vertical, a, b); var area = new PixelRect(0, 0, 1008, 808);
            var next = LayoutInteraction.SnapSeam(root, b.Id, area, 8);
            Equal(506, LayoutEngine.Calculate(next, area, 8).Dividers.Single(d => d.SplitId == b.Id).Bounds.X);
        });
        Run("Handle cache invalidates minima, ratios, bounds, gap and display", () =>
        {
            var root = Grid(); var area = new PixelRect(0, 0, 1008, 808); var cache = new ResizeHandleCache();
            var first = cache.Get("A", root, area, 8);
            for (int i = 0; i < 250; i++) Check(ReferenceEquals(first, cache.Get("A", root, area, 8)));
            Equal(1, cache.CalculationCount);
            cache.Get("A", LayoutEngine.Resize(root, root.Id, .55), area, 8);
            cache.Get("A", root, area with { Width = 1108 }, 8);
            cache.Get("A", root, area, 10);
            var leaf = LayoutEngine.Windows(root).First();
            cache.Get("A", LayoutEngine.Replace(root, leaf.Id, leaf with { Minimum = new(120, 120) }), area, 10);
            cache.Get("B", root, area, 8); Equal(6, cache.CalculationCount);
            cache.Retain(new HashSet<string> { "B" }); Equal(1, cache.EntryCount);
            cache.Clear(); Equal(0, cache.EntryCount);
        });
        Run("Shared ink leaves breaks beside full-opacity local pills", () =>
        {
            var ink = GripInk.Segments(800, new double[] { 200, 600 });
            Equal(2, ink.Count(p => p.Local));
            Check(ink.Where(p => !p.Local).All(p => p.End <= 152 || p.Start >= 248 && p.End <= 552 || p.Start >= 648));
            Check(GripInk.Segments(8, []).Count == 0);
        });
        Run("Session memory reconciles identities, minima and display removal", () =>
        {
            var root = S(SplitAxis.Horizontal, W(1), W(2), .65);
            var snapshot = new SessionLayoutSnapshot(new WorkspaceState().WithRoot("A", root),
                new[] { new SessionWindow(1, 10, new(100, 100)), new SessionWindow(2, 20, new(100, 100)) });
            var same = snapshot.Reconcile(new[] { new SessionWindow(1, 10, new(150, 120)), new SessionWindow(2, 20, new(100, 100)) }, new[] { "A" });
            Equal(root.Id, same.Roots["A"]!.Id); Equal(.65, ((SplitNode)same.Roots["A"]!).Ratio);
            Equal(new PixelSize(150, 120), same.Windows.First().Minimum);
            var reused = snapshot.Reconcile(new[] { new SessionWindow(1, 99, new(100, 100)), new SessionWindow(2, 20, new(100, 100)) }, new[] { "A" });
            Equal(2L, reused.Windows.Single().WindowId);
            Equal(0, snapshot.Reconcile([], new[] { "B" }).Roots.Count);
        });
        Run("Section edge move carries subtree with measured proportions", () =>
        {
            var pair = S(SplitAxis.Vertical, W(1), W(2));
            var root = S(SplitAxis.Horizontal, pair, W(3), .6); var area = new PixelRect(0, 0, 1008, 808);
            var before = LayoutEngine.Calculate(root, area, 8).Regions;
            var moved = LayoutInteraction.MoveSection(root, 3, Placement.Left, area, 8)!;
            Check(((SplitNode)moved).Second is SplitNode);
            var after = LayoutEngine.Calculate(moved, area, 8).Regions;
            foreach (var r in before) Equal(r.Bounds.Width, after.Single(a => a.Window.WindowId == r.Window.WindowId).Bounds.Width);
            Equal(0, after.Single(r => r.Window.WindowId == 3).Bounds.X);
        });
        Run("Repeated work-area squeeze preserves joined seams and returns exactly", () =>
        {
            var reference = S(SplitAxis.Vertical, S(SplitAxis.Horizontal, W(1, 450), W(2)), S(SplitAxis.Horizontal, W(3), W(4, 250)));
            var original = new PixelRect(-1200, 0, 1208, 808); var small = original with { Width = 808 };
            var result = (LayoutNode)reference;
            for (int i = 0; i < 10; i++)
            {
                result = LayoutReflow.PreservingSeams(result, reference, original, small, 8);
                var seams = LayoutEngine.Calculate(result, small, 8).Dividers.Where(d => d.Axis == SplitAxis.Horizontal).ToArray();
                Equal(seams[0].Bounds.X, seams[1].Bounds.X);
                result = LayoutReflow.PreservingSeams(result, reference, original, original, 8);
                Check(LayoutEngine.Calculate(reference, original, 8).Regions.SequenceEqual(LayoutEngine.Calculate(result, original, 8).Regions));
            }
        });
        Run("Capacity planner finds order-independent grouping before evicting", () =>
        {
            // Full-height pane must sit beside the two stacked short panes;
            // contiguous ordering [short, tall, short] cannot represent that cut.
            var windows = new[] { W(1, 300, 300), W(2, 300, 700), W(3, 300, 300) };
            var area = new PixelRect(0, 0, 608, 708);
            var tree = CapacityPlanner.Plan(windows, area, 8)!;
            Equal(3, LayoutEngine.Calculate(tree, area, 8).Regions.Count);
            Equal(3, LayoutEngine.Windows(AutoLayout.Fitting(windows, area, 8, priority: new HashSet<long> { 3 })).Count());
        });
        Run("Priority admission evicts oldest feasible member only", () =>
        {
            var windows = new[] { W(1, 300, 300), W(2, 300, 300), W(3, 300, 300) };
            var tree = AutoLayout.Fitting(windows, new(0, 0, 608, 308), 8, priority: new HashSet<long> { 3 }, leastRecentlyUsed: new long[] { 2, 1, 3 });
            Check(LayoutEngine.Windows(tree).Select(w => w.WindowId).Order().SequenceEqual(new long[] { 1, 3 }));
        });
        Run("Admission reuses evicted idle slot without moving recent neighbor", () =>
        {
            var a = W(1, 300, 300); var b = W(2, 300, 300); var root = S(SplitAxis.Horizontal, a, b, .6);
            var area = new PixelRect(0, 0, 808, 308);
            var before = LayoutEngine.Calculate(root, area, 8).Regions;
            var next = AutoLayout.Fitting(new[] { a, b, W(3, 300, 300) }, area, 8, root, new HashSet<long> { 3 }, new long[] { 2, 1 });
            var after = LayoutEngine.Calculate(next, area, 8).Regions;
            Equal(before.Single(r => r.Window.WindowId == 1).Bounds, after.Single(r => r.Window.WindowId == 1).Bounds);
            Equal(before.Single(r => r.Window.WindowId == 2).Bounds, after.Single(r => r.Window.WindowId == 3).Bounds);
        });
        Run("Impossible incoming app preserves a valid edited tree", () =>
        {
            var root = S(SplitAxis.Horizontal, W(1), W(2), .63);
            var result = AutoLayout.Fitting(LayoutEngine.Windows(root).Append(W(3, 5000, 5000)).ToArray(), new(0, 0, 1008, 808), 8,
                previous: root, priority: new HashSet<long> { 3 });
            Equal(root, result);
        });
        Run("Shared release selects embedded Windows version independently of Mac tag", () =>
        {
            var digest = new string('a', 64);
            using var release = JsonDocument.Parse(JsonSerializer.Serialize(new { tag_name = "macos-v9.0.0", draft = false, prerelease = false,
                body = "Windows 0.3.10", html_url = "https://github.com/AbdullahEgh/Bento-Layout/releases/tag/macos-v9.0.0",
                assets = new[] { new { name = WindowsReleaseCatalog.PackageAsset, browser_download_url = "https://github.com/AbdullahEgh/Bento-Layout/releases/download/macos-v9.0.0/Bento-win-x64.zip", digest = "sha256:" + digest } } }));
            Check(WindowsReleaseCatalog.Parse(release.RootElement, "0.3.9") is null);
            var metadata = new WindowsReleaseMetadata("Bento.Windows", "0.3.10", "win-x64", WindowsReleaseCatalog.PackageAsset, digest);
            var candidate = WindowsReleaseCatalog.Parse(release.RootElement, "0.3.9", metadata)!;
            Equal("0.3.10", candidate.Version);
            Check(WindowsReleaseCatalog.Parse(release.RootElement, "0.3.10", metadata) is null);
            var older = candidate with { Version = "0.3.8" };
            Equal(candidate, WindowsReleaseCatalog.Latest(new[] { older, candidate }));
            bool rejected = false;
            try { WindowsReleaseCatalog.Parse(release.RootElement, "0.3.9", metadata with { Sha256 = new string('b', 64) }); }
            catch (System.IO.InvalidDataException) { rejected = true; }
            Check(rejected);
        });
        Run("Legacy Windows release tags remain compatible and prereleases stay excluded", () =>
        {
            object Release(bool preview) => new { tag_name = "v0.3.10", draft = false, prerelease = preview, body = "Windows update", html_url = "https://github.com/AbdullahEgh/Bento-Layout/releases/tag/v0.3.10",
                assets = new[] { new { name = WindowsReleaseCatalog.PackageAsset, browser_download_url = "https://github.com/AbdullahEgh/Bento-Layout/releases/download/v0.3.10/Bento-win-x64.zip", digest = "sha256:" + new string('a', 64) } } };
            using var stable = JsonDocument.Parse(JsonSerializer.Serialize(Release(false)));
            Equal("0.3.10", WindowsReleaseCatalog.Parse(stable.RootElement, "0.3.9")!.Version);
            using var preview = JsonDocument.Parse(JsonSerializer.Serialize(Release(true)));
            Check(WindowsReleaseCatalog.Parse(preview.RootElement, "0.3.9") is null);
        });
        Run("Physical-edge section gestures exclude slot interiors and other displays", () =>
        {
            var bounds = new PixelRect(-1000, 0, 1000, 800);
            Equal<Placement?>(Placement.Left, LayoutInteraction.ScreenEdge(bounds, new(-999, 400), 20));
            Check(LayoutInteraction.ScreenEdge(bounds, new(-800, 400), 20) is null);
            Check(LayoutInteraction.ScreenEdge(bounds, new(1, 400), 20) is null);
        });
        Run("Motion uses minimum-jerk endpoints and midpoint", () =>
        {
            Equal(0d, Motion.Ease(-1)); Equal(1d, Motion.Ease(2)); Equal(.5, Motion.Ease(.5));
            Check(Motion.Ease(.01) < .00001); Check(Motion.Ease(.99) > .99999);
        });
    }
}
