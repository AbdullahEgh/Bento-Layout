using System.Text.Json;
using System.Text.RegularExpressions;

namespace Bento.Core;

public sealed record WindowsReleaseMetadata(string AppId, string Version, string Platform, string Asset, string Sha256);
public sealed record WindowsReleaseCandidate(string Version, string Notes, string PageUrl, string DownloadUrl, string Digest);
public static class WindowsReleaseCatalog
{
    public const string MetadataAsset = "Bento-windows-release.json";
    public const string PackageAsset = "Bento-win-x64.zip";
    public static WindowsReleaseCandidate? Parse(JsonElement release, string currentVersion, WindowsReleaseMetadata? metadata = null)
    {
        if (release.GetProperty("draft").GetBoolean() || release.GetProperty("prerelease").GetBoolean()) return null;
        string tag = release.GetProperty("tag_name").GetString() ?? "";
        string version;
        if (metadata is not null)
        {
            if (metadata.AppId != "Bento.Windows" || metadata.Platform != "win-x64" || metadata.Asset != PackageAsset ||
                !Regex.IsMatch(metadata.Sha256 ?? "", "^[0-9a-fA-F]{64}$"))
                throw new InvalidDataException("This release has invalid Windows metadata.");
            version = metadata.Version;
        }
        else
        {
            // Legacy Windows tags remain supported. Never derive a Windows
            // version from a macos-v tag, release title, or publication date.
            if (!Regex.IsMatch(tag, @"^[vV]?\d+\.\d+\.\d+(\.\d+)?$")) return null;
            version = tag.TrimStart('v', 'V');
        }
        if (!Version.TryParse(version, out var next)) throw new InvalidDataException("The Windows release version is invalid.");
        if (next <= Version.Parse(currentVersion)) return null;
        foreach (var asset in release.GetProperty("assets").EnumerateArray())
        {
            if (asset.GetProperty("name").GetString() != PackageAsset) continue;
            string url = asset.GetProperty("browser_download_url").GetString() ?? "";
            string digest = asset.TryGetProperty("digest", out var d) ? d.GetString() ?? "" : "";
            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != "https" || uri.Host != "github.com" ||
                !Regex.IsMatch(digest, @"^sha256:[0-9a-fA-F]{64}$"))
                throw new InvalidDataException("This release needs a GitHub asset with a SHA-256 digest.");
            if (metadata is not null && !metadata.Sha256.Equals(digest[7..], StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("The Windows metadata does not match its archive digest.");
            return new(version, release.GetProperty("body").GetString() ?? "", release.GetProperty("html_url").GetString() ?? "", url, digest[7..]);
        }
        throw new InvalidDataException("The Windows release has no Bento-win-x64.zip update package.");
    }
    public static WindowsReleaseCandidate? Latest(IEnumerable<WindowsReleaseCandidate?> candidates) => candidates.Where(c => c is not null)
        .OrderByDescending(c => Version.Parse(c!.Version)).FirstOrDefault();
}
