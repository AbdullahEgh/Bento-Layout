using System.Text.Json;
using System.IO;
using Bento.Core;

namespace Bento.Tests;

internal static class SharedFixtureTests
{
    public static void RunAll()
    {
        using var pack = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "fixtures", "layout-v1.json")));
        Program.Equal(1, pack.RootElement.GetProperty("version").GetInt32());
        foreach (var fixture in pack.RootElement.GetProperty("cases").EnumerateArray())
        {
            Program.Run("Shared contract: " + fixture.GetProperty("name").GetString(), () =>
            {
                var area = fixture.GetProperty("area").EnumerateArray().Select(x => x.GetInt32()).ToArray();
                var bounds = new PixelRect(area[0], area[1], area[2], area[3]);
                var root = ReadNode(fixture.GetProperty("tree"));
                int gap = fixture.GetProperty("gap").GetInt32();
                if (fixture.TryGetProperty("reject", out var reject) && reject.GetBoolean())
                {
                    try { LayoutEngine.Calculate(root, bounds, gap); }
                    catch (LayoutConstraintException) { return; }
                    throw new Exception("Expected the shared impossible layout to be rejected.");
                }
                var result = LayoutEngine.Calculate(root, bounds, gap);
                var expected = fixture.GetProperty("expected");
                Program.Equal(expected.EnumerateObject().Count(), result.Regions.Count);
                foreach (var region in result.Regions)
                {
                    var r = expected.GetProperty(region.Window.WindowId.ToString(System.Globalization.CultureInfo.InvariantCulture)).EnumerateArray().Select(x => x.GetInt32()).ToArray();
                    Program.Equal(new PixelRect(r[0], r[1], r[2], r[3]), region.Bounds);
                }
            });
        }
    }
    private static LayoutNode ReadNode(JsonElement node)
    {
        if (node.TryGetProperty("window", out var id))
        {
            var minimum = node.GetProperty("minimum").EnumerateArray().Select(x => x.GetInt32()).ToArray();
            return WindowNode.Create(id.GetInt64(), new(minimum[0], minimum[1]));
        }
        return new SplitNode(Guid.NewGuid(), node.GetProperty("axis").GetString() == "horizontal" ? SplitAxis.Horizontal : SplitAxis.Vertical,
            node.GetProperty("ratio").GetDouble(), ReadNode(node.GetProperty("first")), ReadNode(node.GetProperty("second")));
    }
}
