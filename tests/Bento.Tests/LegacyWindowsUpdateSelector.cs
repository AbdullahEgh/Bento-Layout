using System.Text.Json;
using System.Text.RegularExpressions;
using Bento.UI;

namespace Bento.Tests;

// Frozen verbatim from shipped Windows v0.3.9 (eae0eda), to prove the
// bootstrap release is consumable BEFORE the new release-list updater arrives.
internal static class LegacyWindowsUpdateSelector
{
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
}
