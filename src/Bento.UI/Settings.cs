using System.Text.Json;

namespace Bento.UI;

public sealed record BentoSettings(uint Modifiers = 3, uint Key = 0x42, int Gap = 8, int Margin = 8,
    int SplitHoldMs = 900, bool Animate = true, int AnimationMs = 140, bool SuppressWindowsSnap = false,
    string Theme = "System", string UpdateRepository = "AbdullahEgh/Bento-Layout", bool CheckUpdates = false, int SchemaVersion = 2,
    int BackgroundDarkness = 50, bool ShortcutEnabled = true, bool MinimizeOverflow = true)
{
    public static string DataDirectory => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Bento");
    private static string PathName => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Bento", "settings.json");
    public static BentoSettings Load()
    {
        try
        {
            return Parse(File.ReadAllText(PathName));
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException) { return new(); }
    }
    public static BentoSettings Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var settings = JsonSerializer.Deserialize<BentoSettings>(json);
        if (settings is null || !settings.IsValid) return new();
        if (!document.RootElement.TryGetProperty("SchemaVersion", out _) && settings.SplitHoldMs == 450)
            settings = settings with { SplitHoldMs = 900 };
        return settings;
    }
    public bool IsValid => Gap is >= 4 and <= 32 && Margin is >= 0 and <= 64 &&
        ((Key is >= 0x30 and <= 0x39) || (Key is >= 0x41 and <= 0x5A)) && Modifiers is > 0 and <= 15 &&
        BackgroundDarkness is >= 0 and <= 100 && SplitHoldMs is >= 0 and <= 2000 && AnimationMs is >= 80 and <= 400 && Theme is "System" or "Light" or "Dark";
    public void Save()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(PathName)!);
        string temporary = PathName + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(this));
        File.Move(temporary, PathName, true);
    }
    public string Shortcut => string.Join("+", new[] {
        (Modifiers & 2) != 0 ? "Ctrl" : null, (Modifiers & 1) != 0 ? "Alt" : null,
        (Modifiers & 4) != 0 ? "Shift" : null, (Modifiers & 8) != 0 ? "Win" : null,
        ((char)Key).ToString() }.Where(s => s is not null));
}
