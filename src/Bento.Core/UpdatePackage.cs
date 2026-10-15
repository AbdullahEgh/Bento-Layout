using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;

namespace Bento.Core;

public sealed record PackageManifest(string AppId, string Version, string Platform, Dictionary<string, string> Files);
public static class UpdatePackage
{
    public const string ManifestName = "bento-release.json";
    public static PackageManifest ValidateDirectory(string directory)
    {
        var manifest = JsonSerializer.Deserialize<PackageManifest>(File.ReadAllText(Path.Combine(directory, ManifestName)))
            ?? throw new InvalidDataException("The update manifest is empty.");
        if (manifest.AppId != "Bento.Windows" || manifest.Platform != "win-x64" || !Version.TryParse(manifest.Version, out _) || manifest.Files is null)
            throw new InvalidDataException("This package is not a Bento Windows update.");
        if (manifest.Files.Count is < 4 or > 128 || !manifest.Files.ContainsKey("Bento.exe") || !manifest.Files.ContainsKey("Bento.dll") ||
            !manifest.Files.ContainsKey("Bento.runtimeconfig.json") || !manifest.Files.ContainsKey("Bento.Updater.exe"))
            throw new InvalidDataException("The update is missing required application files.");
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (name, expected) in manifest.Files)
        {
            if (!SafeName(name) || !names.Add(name) || expected is null || expected.Length != 64)
                throw new InvalidDataException("The update contains an invalid filename or checksum.");
            string path = Path.Combine(directory, name);
            if (!File.Exists(path) || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException($"Missing or invalid update file: {name}");
            using var stream = File.OpenRead(path);
            if (!Convert.ToHexString(SHA256.HashData(stream)).Equals(expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException($"The update checksum does not match: {name}");
        }
        foreach (string path in Directory.EnumerateFileSystemEntries(directory))
            if (Path.GetFileName(path) != ManifestName && !names.Contains(Path.GetFileName(path)))
                throw new InvalidDataException("The update contains files not listed in its manifest.");
        return manifest;
    }
    public static PackageManifest Extract(string archive, string destination)
    {
        if (Directory.Exists(destination) && Directory.EnumerateFileSystemEntries(destination).Any())
            throw new IOException("The update staging folder must be empty.");
        using var zip = ZipFile.OpenRead(archive);
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        long total = 0;
        if (zip.Entries.Count > 129) throw new InvalidDataException("Too many update files.");
        foreach (var entry in zip.Entries)
        {
            if (!SafeName(entry.FullName) || !names.Add(entry.FullName) || entry.Length > 64 * 1024 * 1024 ||
                (total += entry.Length) > 128 * 1024 * 1024 || ((entry.ExternalAttributes >> 16) & 0xF000) == 0xA000)
                throw new InvalidDataException("The update archive has unsafe or duplicate entries.");
        }
        Directory.CreateDirectory(destination);
        foreach (var entry in zip.Entries) entry.ExtractToFile(Path.Combine(destination, entry.FullName));
        return ValidateDirectory(destination);
    }
    public static bool SafeName(string name) => name.Length is > 0 and <= 100 && name != "." && name != ".." &&
        name.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '-' or '_') && !name.EndsWith('.') &&
        !new[] { "CON", "PRN", "AUX", "NUL", "COM1", "LPT1" }.Contains(name.Split('.')[0], StringComparer.OrdinalIgnoreCase);
}

public static class UpdateInstaller
{
    // Both the portable updater and integration tests use this same rollback transaction.
    public static void Apply(string staged, string target, string backup, Action? verifyLaunch = null)
    {
        var manifest = UpdatePackage.ValidateDirectory(staged);
        if (!Directory.Exists(target) || !File.Exists(Path.Combine(target, "Bento.exe"))) throw new IOException("Bento's installation folder was not found.");
        for (var parent = new DirectoryInfo(Path.GetFullPath(target)); parent is not null; parent = parent.Parent)
            if ((parent.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Updating through a linked folder is not supported.");
        Directory.CreateDirectory(backup);
        var copied = new List<string>();
        var saved = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            foreach (string name in manifest.Files.Keys.Append(UpdatePackage.ManifestName))
            {
                string path = Path.Combine(target, name);
                if (File.Exists(path))
                {
                    if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new IOException("An application file is a link.");
                    File.Copy(path, Path.Combine(backup, name), overwrite: false); saved.Add(name);
                }
                copied.Add(name);
                File.Copy(Path.Combine(staged, name), path, overwrite: true);
            }
            verifyLaunch?.Invoke();
        }
        catch
        {
            foreach (string name in copied.AsEnumerable().Reverse())
            {
                string path = Path.Combine(target, name);
                if (saved.Contains(name)) File.Copy(Path.Combine(backup, name), path, overwrite: true);
                else if (File.Exists(path)) File.Delete(path);
            }
            throw;
        }
    }
}
