using System.Diagnostics;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Bento.UI;

public sealed record AvailableUpdate(string Version, string Notes, string PageUrl, string DownloadUrl, string Digest);
public sealed record ReleaseNote(string Version, string Date, string Title, string[] Changes);
public sealed class UpdateService
{
    public static string CurrentVersion => typeof(BentoController).Assembly.GetName().Version?.ToString(3) ?? "0.3.0";
    public static readonly ReleaseNote[] Releases = [
        new("0.3.8", "October 2026", "Settings at any size", ["Resize settings down to a compact phone-width layout, with a page selector and stacked controls.", "Grabber ink appears immediately when pressed and stays separate from its invisible input surface."]),
        new("0.3.7", "October 2026", "A quieter, smoother workspace", ["Settings and layouts save automatically, with no Save buttons.", "Grabbers appear on hover or while held, below application windows and above the dimmer.", "Activation and restoration use smooth transitions; previews show swap, split and conflict symbols without text.", "Extra windows minimize to the taskbar. Reopening one gives it priority in the split layout; turning Bento off restores Bento-minimized windows."]),
        new("0.3.6", "October 2026", "Settings stay where you leave them", ["Bento settings behave like a normal window. Switching to another app keeps that app in front.", "Desktop grip maintenance no longer brings settings back above other applications."]),
        new("0.3.5", "October 2026", "Ready when you sign in", ["Start at login is available in Workspace. Save changes to enable or disable it for your Windows account.", "Bento opens quietly in the tray on sign-in, using the current installation folder.", "Left-click the tray icon to toggle Bento; right-click for its menu."]),
        new("0.3.4", "October 2026", "One click, two workspaces", ["Click the tray icon or press Ctrl+Alt+B to toggle Bento; change or disable the shortcut in Gestures.", "Save Bento keeps a reusable layout locally for future launches.", "Distinct active and inactive tray icons, with a grouped menu that follows Windows appearance.", "A longer, slim held grabber with quick, smooth fade and length transitions."]),
        new("0.3.3", "October 2026", "Windows that follow your hand", ["Neighboring windows resize live as you drag a divider.", "The active grabber gets longer while keeping its original slim thickness.", "Grabbers stay bright above the dark background and below settings.", "A softer glass slot preview with aligned corners and subtle highlights."]),
        new("0.3.2", "October 2026", "Small controls, clearer feedback", ["Dim the background beneath the layout from clear to black, with 50% darkness by default.", "Original icons illustrate every setting and main action.", "Dragging a divider shows a longer, solid grabber instead of a full-length line.", "Grabbers adapt to wallpaper and background darkness; pausing removes the dimmer.", "What's New shows the latest version, with older releases in a nested Update Log."]),
        new("0.3.1", "October 2026", "Quieter, clearer gestures", ["Split previews stay within the existing slot, with a text-free acrylic surface.", "A longer 900 ms hold, adjustable up to two seconds.", "Light text in dark mode and live Windows appearance updates.", "Longer dividers appear individually on hover or touch, adapt to wallpaper, and stay behind settings."]),
        new("0.3.0", "October 2026", "A desktop that follows your lead", ["Hold at a window edge to split, with visible progress and stable targets.", "Smoother window transitions, with a reduced-motion option.", "A new Bento interface, light and dark appearances, and original icons.", "Optional Windows edge-snap control with restoration on exit.", "GitHub release checks, verified update packages, and update history."]),
        new("0.2.1", "October 2026", "Lighter dragging", ["Reuse previews within the same destination zone.", "Reduce application queries at drag start."]),
        new("0.2.0", "October 2026", "Bento on your desktop", ["Automatic recursive layouts for real application windows.", "Drag to swap or split, resize neighboring regions, and undo arrangements."])
    ];
    public static string NormalizeRepository(string input)
    {
        string value = input.Trim().TrimEnd('/');
        if (value.StartsWith("https://github.com/", StringComparison.OrdinalIgnoreCase)) value = value[19..];
        if (!Regex.IsMatch(value, @"^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}$") || value.EndsWith("/.") || value.EndsWith("/.."))
            throw new ArgumentException("Enter a GitHub repository as owner/Bento-Layout.");
        return value;
    }
    private static HttpClient Client()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd($"Bento/{CurrentVersion}");
        return client;
    }
    public async System.Threading.Tasks.Task<AvailableUpdate?> CheckAsync(string repository, System.Threading.CancellationToken cancellation = default)
    {
        string repo = NormalizeRepository(repository);
        using var client = Client();
        using var response = await client.GetAsync($"https://api.github.com/repos/{repo}/releases/latest", cancellation);
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            throw new InvalidOperationException("No public release is available yet. For a private repository, download its update package from GitHub.");
        response.EnsureSuccessStatusCode();
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellation));
        return ParseRelease(document.RootElement, CurrentVersion);
    }
    public static AvailableUpdate? ParseRelease(JsonElement release, string currentVersion)
    {
        string version = (release.GetProperty("tag_name").GetString() ?? "").TrimStart('v', 'V');
        if (!Version.TryParse(version, out var next) || next <= Version.Parse(currentVersion) ||
            release.GetProperty("draft").GetBoolean() || release.GetProperty("prerelease").GetBoolean()) return null;
        foreach (var asset in release.GetProperty("assets").EnumerateArray())
        {
            if (asset.GetProperty("name").GetString() != "Bento-win-x64.zip") continue;
            string url = asset.GetProperty("browser_download_url").GetString() ?? "";
            string digest = asset.TryGetProperty("digest", out var d) ? d.GetString() ?? "" : "";
            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != "https" || uri.Host != "github.com" ||
                !Regex.IsMatch(digest, @"^sha256:[0-9a-fA-F]{64}$"))
                throw new InvalidDataException("This release needs a GitHub asset with a SHA-256 digest.");
            return new(version, release.GetProperty("body").GetString() ?? "", release.GetProperty("html_url").GetString() ?? "", url, digest[7..]);
        }
        throw new InvalidDataException("The latest release has no Bento-win-x64.zip update package.");
    }
    public async System.Threading.Tasks.Task<string> DownloadAsync(AvailableUpdate update, System.Threading.CancellationToken cancellation = default)
    {
        string folder = Path.Combine(BentoSettings.DataDirectory, "Updates", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        string path = Path.Combine(folder, "Bento-win-x64.zip");
        using var client = Client();
        using var response = await client.GetAsync(update.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, cancellation);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength > 128 * 1024 * 1024) throw new InvalidDataException("The update package is too large.");
        await using (var input = await response.Content.ReadAsStreamAsync(cancellation))
        await using (var output = File.Create(path))
        {
            byte[] buffer = new byte[81920]; long length = 0; int count;
            while ((count = await input.ReadAsync(buffer, cancellation)) > 0)
            {
                if ((length += count) > 128 * 1024 * 1024) throw new InvalidDataException("The update package is too large.");
                await output.WriteAsync(buffer.AsMemory(0, count), cancellation);
            }
        }
        using var file = File.OpenRead(path);
        if (!Convert.ToHexString(SHA256.HashData(file)).Equals(update.Digest, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("The download could not be verified. Try checking for updates again.");
        return path;
    }
    public static (string Directory, PackageManifest Manifest) Stage(string package)
    {
        string folder = Path.Combine(BentoSettings.DataDirectory, "Updates", Guid.NewGuid().ToString("N"), "package");
        var manifest = UpdatePackage.Extract(package, folder);
        if (Version.Parse(manifest.Version) < Version.Parse(CurrentVersion)) throw new InvalidDataException("An older update cannot replace this version of Bento.");
        return (folder, manifest);
    }
    public static void Install(string staged, PackageManifest manifest)
    {
        // Run the currently installed, trusted helper from a separate directory, never a helper from the incoming ZIP.
        string helper = Path.Combine(Path.GetDirectoryName(staged)!, "helper"); Directory.CreateDirectory(helper);
        foreach (string name in new[] { "Bento.Updater.exe", "Bento.Updater.dll", "Bento.Updater.deps.json", "Bento.Updater.runtimeconfig.json", "Bento.Core.dll" })
            File.Copy(Path.Combine(AppContext.BaseDirectory, name), Path.Combine(helper, name));
        string job = Path.Combine(helper, "job.json");
        using var current = Process.GetCurrentProcess();
        File.WriteAllText(job, JsonSerializer.Serialize(new { Staged = staged, Target = AppContext.BaseDirectory, ProcessId = Environment.ProcessId,
            StartTimeUtcTicks = current.StartTime.ToUniversalTime().Ticks, manifest.Version }));
        var info = new ProcessStartInfo(Path.Combine(helper, "Bento.Updater.exe")) { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = helper };
        info.ArgumentList.Add(job);
        using var helperProcess = Process.Start(info) ?? throw new IOException("The updater could not start. Bento is still running.");
        Application.Current.Shutdown();
    }
}
