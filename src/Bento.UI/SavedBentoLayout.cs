using System.Text.Json;

namespace Bento.UI;

public sealed record SavedBentoNode(string? Application, string? Title, SplitAxis Axis, double Ratio, SavedBentoNode? First, SavedBentoNode? Second);
public sealed record SavedBentoLayout(Dictionary<string, SavedBentoNode?> Monitors)
{
    private static string FileName => Path.Combine(BentoSettings.DataDirectory, "saved-layout.json");
    private static string Identity(AppWindow window)
    {
        try
        {
            using var process = System.Diagnostics.Process.GetProcessById((int)window.ProcessId);
            try { return process.MainModule?.FileName ?? process.ProcessName; }
            catch { return process.ProcessName; }
        }
        catch { return "title:" + window.Title; }
    }
    public static SavedBentoLayout Capture(WorkspaceState state, IReadOnlyList<AppWindow> windows, Func<AppWindow, string>? identity = null)
    {
        identity ??= Identity;
        SavedBentoNode? SaveNode(LayoutNode? node) => node switch
        {
            WindowNode leaf when windows.FirstOrDefault(w => w.Id == leaf.WindowId) is { } window => new(identity(window), window.Title, default, 0, null, null),
            SplitNode split => new(null, null, split.Axis, split.Ratio, SaveNode(split.First), SaveNode(split.Second)),
            _ => null
        };
        return new(state.Roots.ToDictionary(p => p.Key, p => SaveNode(p.Value)));
    }
    public WorkspaceState Restore(IReadOnlyList<AppWindow> windows, IEnumerable<string> monitorIds, Func<AppWindow, string>? identity = null)
    {
        identity ??= Identity;
        var available = windows.Select(w => (Window: w, Key: identity(w))).ToList();
        LayoutNode? RestoreNode(SavedBentoNode? node, int depth)
        {
            if (node is null) return null;
            if (depth > 64) throw new InvalidDataException("The saved Bento layout is too deep.");
            if (node.Application is { } application)
            {
                int index = available.FindIndex(w => w.Key.Equals(application, StringComparison.OrdinalIgnoreCase) && w.Window.Title == node.Title);
                if (index < 0) index = available.FindIndex(w => w.Key.Equals(application, StringComparison.OrdinalIgnoreCase));
                if (index < 0) return null;
                var window = available[index].Window; available.RemoveAt(index);
                return WindowNode.Create(window.Id, window.Minimum);
            }
            if (!Enum.IsDefined(node.Axis) || !double.IsFinite(node.Ratio) || node.Ratio <= 0 || node.Ratio >= 1)
                throw new InvalidDataException("The saved Bento layout has an invalid divider.");
            var first = RestoreNode(node.First, depth + 1); var second = RestoreNode(node.Second, depth + 1);
            return first is null ? second : second is null ? first : new SplitNode(Guid.NewGuid(), node.Axis, node.Ratio, first, second);
        }
        return new(monitorIds.Select(id => new KeyValuePair<string, LayoutNode?>(id, RestoreNode(Monitors.GetValueOrDefault(id), 0))));
    }
    public void Save()
    {
        Directory.CreateDirectory(BentoSettings.DataDirectory);
        File.WriteAllText(FileName + ".tmp", JsonSerializer.Serialize(this));
        File.Move(FileName + ".tmp", FileName, true);
    }
    public static SavedBentoLayout? Load()
    {
        try { return JsonSerializer.Deserialize<SavedBentoLayout>(File.ReadAllText(FileName)); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException) { return null; }
    }
}
