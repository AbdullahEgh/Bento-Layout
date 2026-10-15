using System.Diagnostics;
using System.Text.Json;
using Bento.Core;

if (args.Length != 1) return 2;
var job = JsonSerializer.Deserialize<UpdateJob>(File.ReadAllText(args[0])) ?? throw new InvalidDataException("Missing update job.");
string logDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Bento");
Directory.CreateDirectory(logDirectory);
try
{
    try
    {
        using var previous = Process.GetProcessById(job.ProcessId);
        if (previous.StartTime.ToUniversalTime().Ticks == job.StartTimeUtcTicks && !previous.WaitForExit(60000))
            throw new IOException("Bento is still running. Close it and try the update again.");
    }
    catch (ArgumentException) { /* The previous process has already exited. */ }
    string backup = Path.Combine(Path.GetDirectoryName(job.Staged)!, "backup");
    string lockFile = Path.Combine(job.Target, ".bento-update.lock");
    using (var installLock = new FileStream(lockFile, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None, 1, FileOptions.DeleteOnClose))
        UpdateInstaller.Apply(job.Staged, job.Target, backup, () =>
        {
            var process = Process.Start(new ProcessStartInfo(Path.Combine(job.Target, "Bento.exe")) { UseShellExecute = false, WorkingDirectory = job.Target, CreateNoWindow = true })
                ?? throw new IOException("The updated app could not start.");
            using (process)
                if (process.WaitForExit(2500)) throw new IOException("The updated app exited during startup. The previous version was restored.");
        });
    File.AppendAllText(Path.Combine(logDirectory, "update-history.jsonl"), JsonSerializer.Serialize(new { Time = DateTimeOffset.UtcNow, job.Version, Success = true, Message = "Update installed." }) + Environment.NewLine);
    return 0;
}
catch (Exception ex)
{
    File.AppendAllText(Path.Combine(logDirectory, "update-history.jsonl"), JsonSerializer.Serialize(new { Time = DateTimeOffset.UtcNow, job.Version, Success = false, Message = ex.Message }) + Environment.NewLine);
    try { Process.Start(new ProcessStartInfo(Path.Combine(job.Target, "Bento.exe"), "--updates") { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = job.Target }); } catch { }
    return 1;
}
internal sealed record UpdateJob(string Staged, string Target, int ProcessId, long StartTimeUtcTicks, string Version);
