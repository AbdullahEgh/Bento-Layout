using Bento.Core;
using Bento.Windows;

namespace Bento.Tests;

// Deliberately dependency-free: tests run offline with the SDK, without a NuGet test adapter.
internal static class Program
{
    private static int passed, failed;
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.FirstOrDefault() == "--verify-update-package")
        {
            Run("Built package remains compatible with the shipped Windows OTA selector", () =>
            {
                string folder = Path.Combine(Path.GetTempPath(), "Bento-package-" + Guid.NewGuid().ToString("N"));
                try
                {
                    var manifest = UpdatePackage.Extract(args[1], folder);
                    Equal("Bento.Windows", manifest.AppId); Equal("win-x64", manifest.Platform); Equal(Bento.UI.UpdateService.CurrentVersion, manifest.Version);
                    string digest = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(args[1])));
                    using var release = System.Text.Json.JsonDocument.Parse(System.Text.Json.JsonSerializer.Serialize(new {
                        tag_name = "v" + manifest.Version, draft = false, prerelease = false, body = "Windows update", html_url = "https://github.com/AbdullahEgh/Bento-Layout/releases/tag/v" + manifest.Version,
                        assets = new[] {
                            new { name = "Bento-macos-universal.zip", browser_download_url = "https://github.com/AbdullahEgh/Bento-Layout/releases/download/v" + manifest.Version + "/Bento-macos-universal.zip", digest = "sha256:" + new string('0',64) },
                            new { name = "Bento-win-x64.zip", browser_download_url = "https://github.com/AbdullahEgh/Bento-Layout/releases/download/v" + manifest.Version + "/Bento-win-x64.zip", digest = "sha256:" + digest }
                        }
                    }));
                    var legacy = LegacyWindowsUpdateSelector.ParseRelease(release.RootElement, "0.3.9");
                    Check(legacy is not null); Equal(manifest.Version, legacy!.Version); Equal(digest, legacy.Digest);
                    Equal(legacy, Bento.UI.UpdateService.ParseRelease(release.RootElement, "0.3.9"));
                    Check(LegacyWindowsUpdateSelector.ParseRelease(release.RootElement, manifest.Version) is null);
                }
                finally { if (Directory.Exists(folder)) Directory.Delete(folder, true); }
            });
            Console.WriteLine($"RESULT: {passed} passed, {failed} failed"); return failed == 0 ? 0 : 1;
        }
        if (args.FirstOrDefault() == "--fixture") return NativeTests.Fixture(args[1]);
        if (args.Contains("--settings-order-smoke"))
        {
            NativeTests.SettingsOrderSmoke();
            Console.WriteLine($"RESULT: {passed} passed, {failed} failed");
            return failed == 0 ? 0 : 1;
        }
        if (args.Contains("--interactive"))
        {
            int countIndex = Array.IndexOf(args, "--windows");
            int fixtureCount = 3;
            if (countIndex >= 0 && (countIndex + 1 >= args.Length || !int.TryParse(args[countIndex + 1], out fixtureCount) || fixtureCount is < 3 or > 12))
            {
                Console.Error.WriteLine("--windows requires a count from 3 to 12.");
                return 1;
            }
            NativeTests.RunAll(interactive: true, fixtureCount: fixtureCount);
            return failed == 0 ? 0 : 1;
        }
        SharedFixtureTests.RunAll();
        ParityGeometryTests.RunAll();
        PlatformParityTests.RunAll();
        Run("Empty workspace", () => Equal(0, LayoutEngine.Calculate(null, Area).Regions.Count));
        Run("First window fills work area", () => Equal(Area, LayoutEngine.Calculate(W(1), Area).Regions.Single().Bounds));
        Run("Automatic empty layout", () => Check(AutoLayout.Arrange([], Area) is null));
        for (int count = 1; count <= 12; count++)
        {
            int n = count;
            Run($"Automatic layout includes all {n} windows", () =>
            {
                var root = AutoLayout.Arrange(Enumerable.Range(1, n).Select(i => W(i)).ToArray(), Area);
                var result = LayoutEngine.Calculate(root, Area);
                Equal(n, result.Regions.Count); Equal(n - 1, result.Dividers.Count); AssertTiling(result.Regions, Area);
                Equal(n, result.Regions.Select(r => r.Window.WindowId).Distinct().Count());
            });
        }
        Run("Overflow fitting retains usable windows", () =>
        {
            var huge = WindowNode.Create(99, new PixelSize(5000, 5000));
            var root = AutoLayout.Fitting([W(1), huge, W(2)], Area);
            Equal(2, LayoutEngine.Windows(root).Count());
            Check(!LayoutEngine.Windows(root).Any(w => w.WindowId == 99));
        });
        Run("Reopened window gets priority over occupied slots", () =>
        {
            var large = WindowNode.Create(3, new PixelSize(700, 700));
            var small = new[] { WindowNode.Create(1, new PixelSize(300, 300)), WindowNode.Create(2, new PixelSize(300, 300)) };
            var area = new PixelRect(0, 0, 900, 800);
            var root = AutoLayout.Fitting(small.Append(large).ToArray(), area, previous: AutoLayout.Arrange(small, area), priority: new HashSet<long> { 3 });
            Equal(3L, LayoutEngine.Windows(root).Single().WindowId);
        });
        Run("Automatic portrait layout", () =>
        { var a = new PixelRect(-1200, 0, 1080, 1920); AssertTiling(LayoutEngine.Calculate(AutoLayout.Arrange([W(1), W(2), W(3)], a), a).Regions, a); });
        Run("Automatic impossible layout reports constraints", () => Throws<LayoutConstraintException>(() => AutoLayout.Arrange([W(1), W(2)], new(0, 0, 200, 150))));
        Run("Automatic duplicate window rejected", () => Throws<ArgumentException>(() => AutoLayout.Arrange([W(1), W(1)], Area)));
        Run("Automatic constraint search handles asymmetric minima", () =>
        { var a = new PixelRect(0, 0, 1000, 600); AssertTiling(LayoutEngine.Calculate(AutoLayout.Arrange([WindowNode.Create(1, new(750, 300)), W(2)], a), a).Regions, a); });
        Run("Automatic insertion retains existing split identity and ratio", () =>
        {
            var original = (SplitNode)Three().Roots["A"]!;
            original = original with { Ratio = .65 };
            var next = (SplitNode)AutoLayout.Insert(original, W(4), Area);
            Equal(original.Id, next.Id); Equal(original.Ratio, next.Ratio); Equal(4, LayoutEngine.Windows(next).Count());
        });
        foreach (var direction in new[] { Placement.Left, Placement.Right, Placement.Top, Placement.Bottom })
        {
            Run($"Insert {direction}", () =>
            {
                var a = W(1); var state = new WorkspaceState().Place("A", null, a, Placement.Center).Place("A", a.Id, W(2), direction);
                var regions = LayoutEngine.Calculate(state.Roots["A"], Area).Regions;
                Equal(2, regions.Count); AssertTiling(regions, Area);
                var incoming = regions.Single(r => r.Window.WindowId == 2).Bounds;
                Check(direction switch { Placement.Left => incoming.X == Area.X, Placement.Right => incoming.Right == Area.Right,
                    Placement.Top => incoming.Y == Area.Y, _ => incoming.Bottom == Area.Bottom });
            });
        }
        Run("Three windows form recursive layout", () =>
        {
            var state = Three(); var r = LayoutEngine.Calculate(state.Roots["A"], Area);
            Equal(3, r.Regions.Count); Equal(2, r.Dividers.Count); AssertTiling(r.Regions, Area);
        });
        Run("Removal collapses parent and expands sibling", () =>
        {
            var state = Three().Remove(3); var regions = LayoutEngine.Calculate(state.Roots["A"], Area).Regions;
            Equal(2, regions.Count); Equal(Area.Height, regions.Single(r => r.Window.WindowId == 2).Bounds.Height);
        });
        Run("Remove final window leaves empty root", () => Equal(0, Three().Remove(1).Remove(2).Remove(3).Windows.Count()));
        Run("Unknown removal preserves leaves", () => Equal(3, Three().Remove(999).Windows.Count()));
        Run("Moving window never duplicates it", () =>
        {
            var state = Three(); var target = state.Windows.First(w => w.WindowId == 1); var source = state.Windows.First(w => w.WindowId == 3);
            state = state.Place("A", target.Id, source, Placement.Top);
            Equal(3, state.Windows.Count()); Equal(3, state.Windows.Select(w => w.WindowId).Distinct().Count());
        });
        Run("Center swaps managed windows", () =>
        {
            var state = Three(); var before = LayoutEngine.Calculate(state.Roots["A"], Area).Regions;
            var source = state.Windows.First(w => w.WindowId == 1); var target = state.Windows.First(w => w.WindowId == 3);
            var next = state.Place("A", target.Id, source, Placement.Center);
            var after = LayoutEngine.Calculate(next.Roots["A"], Area).Regions;
            Equal(before.Single(r => r.Window.WindowId == 1).Bounds, after.Single(r => r.Window.WindowId == 3).Bounds);
            Equal(before.Single(r => r.Window.WindowId == 3).Bounds, after.Single(r => r.Window.WindowId == 1).Bounds);
        });
        Run("Center replaces floating window", () =>
        {
            var state = Three(); var target = state.Windows.First();
            var next = state.Place("A", target.Id, W(4), Placement.Center);
            Equal(3, next.Windows.Count()); Check(!next.Windows.Any(w => w.WindowId == target.WindowId));
        });
        Run("Self drop is unchanged", () =>
        { var state = Three(); var w = state.Windows.First(); Check(ReferenceEquals(state, state.Place("A", w.Id, w, Placement.Left))); });
        Run("Occupied monitor requires an explicit region", () => Throws<ArgumentException>(() => Three().Place("A", null, W(9), Placement.Left)));
        Run("Move across monitors collapses source", () =>
        {
            var state = Three(); var w = state.Windows.First(); state = state.Place("B", null, w, Placement.Center);
            Equal(2, LayoutEngine.Windows(state.Roots["A"]).Count()); Equal(w.WindowId, LayoutEngine.Windows(state.Roots["B"]).Single().WindowId);
        });
        Run("Center swaps across monitors", () =>
        {
            var a = W(1); var b = W(2); var state = new WorkspaceState().Place("A", null, a, Placement.Center).Place("B", null, b, Placement.Center);
            state = state.Place("B", b.Id, a, Placement.Center);
            Equal(2L, LayoutEngine.Windows(state.Roots["A"]).Single().WindowId); Equal(1L, LayoutEngine.Windows(state.Roots["B"]).Single().WindowId);
        });
        Run("Constraints reject impossible insertion", () => Throws<LayoutConstraintException>(() => LayoutEngine.Calculate(Three().Roots["A"], new(0, 0, 200, 100))));
        Run("Divider clamps to descendant minima", () =>
        {
            var state = Three(); var root = (SplitNode)state.Roots["A"]!;
            var result = LayoutEngine.Calculate(LayoutEngine.Resize(root, root.Id, .999), Area);
            Check(result.Regions.All(r => r.Bounds.Width >= r.Window.Minimum.Width && r.Bounds.Height >= r.Window.Minimum.Height));
        });
        Run("Native right edge resize updates the ancestor split", () =>
        {
            var root = Three().Roots["A"]!; var old = LayoutEngine.Calculate(root, Area).Regions.Single(r => r.Window.WindowId == 1).Bounds;
            var requested = old with { Width = old.Width + 100 };
            var next = LayoutEngine.ResizeWindow(root, 1, requested, Area);
            Equal(requested, LayoutEngine.Calculate(next, Area).Regions.Single(r => r.Window.WindowId == 1).Bounds);
        });
        Run("Native left edge resize keeps the trailing edge in place", () =>
        {
            var root = Three().Roots["A"]!; var old = LayoutEngine.Calculate(root, Area).Regions.Single(r => r.Window.WindowId == 2).Bounds;
            var requested = old with { X = old.X - 80, Width = old.Width + 80 };
            var next = LayoutEngine.ResizeWindow(root, 2, requested, Area);
            Equal(requested, LayoutEngine.Calculate(next, Area).Regions.Single(r => r.Window.WindowId == 2).Bounds);
        });
        Run("Native top edge resize updates only the inner boundary", () =>
        {
            var root = Three().Roots["A"]!; var old = LayoutEngine.Calculate(root, Area).Regions.Single(r => r.Window.WindowId == 3).Bounds;
            var requested = old with { Y = old.Y + 50, Height = old.Height - 50 };
            Equal(requested, LayoutEngine.Calculate(LayoutEngine.ResizeWindow(root, 3, requested, Area), Area).Regions.Single(r => r.Window.WindowId == 3).Bounds);
        });
        Run("Native outer edge resize does not change the monitor boundary", () =>
        {
            var root = Three().Roots["A"]!; var old = LayoutEngine.Calculate(root, Area).Regions.Single(r => r.Window.WindowId == 1).Bounds;
            Check(ReferenceEquals(root, LayoutEngine.ResizeWindow(root, 1, old with { X = -100, Width = old.Width + 100 }, Area)));
        });
        Run("Native resize clamps to neighboring minimum sizes", () =>
        {
            var root = Three().Roots["A"]!; var old = LayoutEngine.Calculate(root, Area).Regions.Single(r => r.Window.WindowId == 1).Bounds;
            AssertTiling(LayoutEngine.Calculate(LayoutEngine.ResizeWindow(root, 1, old with { Width = 1900 }, Area), Area).Regions, Area);
        });
        Run("Native resize leaves an unrelated branch unchanged", () =>
        {
            var a = new SplitNode(Guid.NewGuid(), SplitAxis.Vertical, .5, W(1), W(2));
            var b = new SplitNode(Guid.NewGuid(), SplitAxis.Vertical, .5, W(3), W(4));
            var root = new SplitNode(Guid.NewGuid(), SplitAxis.Horizontal, .5, a, b);
            var before = LayoutEngine.Calculate(root, Area).Regions;
            var source = before.Single(r => r.Window.WindowId == 1).Bounds;
            var after = LayoutEngine.Calculate(LayoutEngine.ResizeWindow(root, 1, source with { Height = source.Height + 70 }, Area), Area).Regions;
            Equal(before.Single(r => r.Window.WindowId == 3).Bounds, after.Single(r => r.Window.WindowId == 3).Bounds);
        });
        Run("Native corner resize adjusts both ancestor axes", () =>
        {
            var root = Three().Roots["A"]!; var old = LayoutEngine.Calculate(root, Area).Regions.Single(r => r.Window.WindowId == 2).Bounds;
            var requested = old with { X = old.X - 80, Width = old.Width + 80, Height = old.Height + 70 };
            Equal(requested, LayoutEngine.Calculate(LayoutEngine.ResizeWindow(root, 2, requested, Area), Area).Regions.Single(r => r.Window.WindowId == 2).Bounds);
        });
        Run("Native resize of an unknown window leaves the tree unchanged", () =>
        { var root = Three().Roots["A"]!; Check(ReferenceEquals(root, LayoutEngine.ResizeWindow(root, 999, Area, Area))); });
        Run("NaN ratio rejected", () => Throws<LayoutConstraintException>(() => LayoutEngine.Calculate(new SplitNode(Guid.NewGuid(), SplitAxis.Horizontal, double.NaN, W(1), W(2)), Area)));
        Run("Negative gap rejected", () => Throws<ArgumentOutOfRangeException>(() => LayoutEngine.Calculate(W(1), Area, -1)));
        Run("Negative monitor origin remains physical", () =>
        { var area = new PixelRect(-2560, -200, 2560, 1440); AssertTiling(LayoutEngine.Calculate(Three().Roots["A"], area).Regions, area); });
        Run("Odd pixel sizes have no accumulated drift", () =>
        { var area = new PixelRect(0, 0, 1919, 1079); AssertTiling(LayoutEngine.Calculate(Three().Roots["A"], area).Regions, area); });
        Run("Undo and redo preserve immutable state", () =>
        {
            var history = new LayoutHistory(); var initial = history.Current; var state = Three(); history.Commit(state);
            Check(ReferenceEquals(initial, history.Undo())); Check(ReferenceEquals(state, history.Redo())); Equal(0, initial.Windows.Count());
        });
        Run("Commit after undo clears redo", () =>
        { var h = new LayoutHistory(); h.Commit(Three()); h.Undo(); var s = new WorkspaceState().Place("A", null, W(9), Placement.Center); h.Commit(s); Check(ReferenceEquals(s, h.Redo())); });
        Run("History is bounded to 100 changes", () =>
        { var h = new LayoutHistory(); for (int i = 1; i <= 120; i++) h.Commit(new WorkspaceState().Place("A", null, W(i), Placement.Center)); for (int i = 0; i < 150; i++) h.Undo(); Equal(20L, h.Current.Windows.Single().WindowId); });
        foreach (var (point, zone) in new[] { (new PixelPoint(10, 500), Placement.Left), (new PixelPoint(990, 500), Placement.Right),
            (new PixelPoint(500, 10), Placement.Top), (new PixelPoint(500, 990), Placement.Bottom), (new PixelPoint(500, 500), Placement.Center) })
            Run($"Zone {zone}", () => Equal(zone, PlacementZones.HitTest(new(0, 0, 1000, 1000), point)));
        Run("Outside zone is rejected", () => Throws<ArgumentOutOfRangeException>(() => PlacementZones.HitTest(Area, new(-1, -1))));
        Run("DWM frame compensation at negative origin", () => Equal(new PixelRect(-1928, 0, 976, 1048),
            Geometry.CompensateFrame(new(-1920, 0, 960, 1040), new(92, 100, 816, 608), new(100, 100, 800, 600))));
        Run("Random recursive layouts preserve geometry (1000 operations)", Randomized);
        InteractionTests.RunAll();
        if (args.Contains("--native")) NativeTests.RunAll();
        else Console.WriteLine("SKIP native desktop integration (run with --native on an interactive Windows desktop)");
        Console.WriteLine($"RESULT: {passed} passed, {failed} failed");
        return failed == 0 ? 0 : 1;
    }
    internal static PixelRect Area => new(0, 0, 1920, 1040);
    private static WindowNode W(long id) => WindowNode.Create(id, new(180, 120));
    private static WorkspaceState Three()
    {
        var a = W(1); var b = W(2);
        return new WorkspaceState().Place("A", null, a, Placement.Center).Place("A", a.Id, b, Placement.Right).Place("A", b.Id, W(3), Placement.Bottom);
    }
    private static void Randomized()
    {
        var random = new Random(42); var state = new WorkspaceState();
        for (int i = 1; i <= 1000; i++)
        {
            var windows = state.Windows.ToArray();
            if (windows.Length > 0 && random.Next(3) == 0) state = state.Remove(windows[random.Next(windows.Length)].WindowId);
            else
            {
                var target = windows.Length == 0 ? null : windows[random.Next(windows.Length)];
                var next = state.Place("A", target?.Id, W(i), (Placement)random.Next(5));
                try { LayoutEngine.Calculate(next.Roots["A"], Area); state = next; } catch (LayoutConstraintException) { }
            }
            var result = LayoutEngine.Calculate(state.Roots.GetValueOrDefault("A"), Area);
            AssertTiling(result.Regions, Area);
            Equal(state.Windows.Count(), state.Windows.Select(w => w.WindowId).Distinct().Count());
        }
    }
    private static void AssertTiling(IReadOnlyList<Region> regions, PixelRect area)
    {
        for (int i = 0; i < regions.Count; i++)
        {
            var a = regions[i].Bounds;
            Check(a.X >= area.X && a.Y >= area.Y && a.Right <= area.Right && a.Bottom <= area.Bottom);
            Check(a.Width >= regions[i].Window.Minimum.Width && a.Height >= regions[i].Window.Minimum.Height);
            for (int j = i + 1; j < regions.Count; j++)
            { var b = regions[j].Bounds; Check(a.Right <= b.X || b.Right <= a.X || a.Bottom <= b.Y || b.Bottom <= a.Y); }
        }
        if (regions.Count > 0)
        {
            Equal(area.X, regions.Min(r => r.Bounds.X)); Equal(area.Y, regions.Min(r => r.Bounds.Y));
            Equal(area.Right, regions.Max(r => r.Bounds.Right)); Equal(area.Bottom, regions.Max(r => r.Bounds.Bottom));
        }
    }
    internal static void Run(string name, Action test)
    {
        try { test(); passed++; Console.WriteLine($"PASS {name}"); }
        catch (Exception ex) { failed++; Console.WriteLine($"FAIL {name}: {ex}"); }
    }
    internal static void Check(bool value) { if (!value) throw new Exception("Assertion failed."); }
    internal static void Equal<T>(T expected, T actual) { if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new Exception($"Expected {expected}; got {actual}."); }
    private static void Throws<T>(Action action) where T : Exception
    { try { action(); } catch (T) { return; } throw new Exception($"Expected {typeof(T).Name}."); }
}
