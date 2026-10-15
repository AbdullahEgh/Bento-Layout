using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Bento.Windows;

public static class WindowSnapping
{
    public static bool Enabled
    {
        get
        {
            if (!GetParameter(0x0082, 0, out int enabled, 0)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return enabled != 0;
        }
        set
        {
            // Session-only: do not write the user's persistent Windows preference.
            if (!SetParameter(0x0083, 0, value ? 1 : 0, 2)) throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }
    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
    private static extern bool GetParameter(uint action, uint param, out int value, uint flags);
    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
    private static extern bool SetParameter(uint action, uint param, nint value, uint flags);
}

// Restores the exact original preference on exit; a journal also permits recovery after a crash.
public sealed class SnapLease : IDisposable
{
    private readonly string journal;
    private readonly Func<bool> read;
    private readonly Action<bool> write;
    private bool? original;
    public SnapLease(string journal, Func<bool>? read = null, Action<bool>? write = null)
    {
        this.journal = journal; this.read = read ?? (() => WindowSnapping.Enabled); this.write = write ?? (v => WindowSnapping.Enabled = v);
        if (File.Exists(journal) && bool.TryParse(File.ReadAllText(journal), out bool saved))
        {
            // If somebody re-enabled snapping after a crash, preserve that newer user choice.
            if (!this.read()) this.write(saved);
            File.Delete(journal);
        }
    }
    public void SetSuppressed(bool suppress)
    {
        if (suppress)
        {
            if (original.HasValue) return;
            bool saved = read();
            Directory.CreateDirectory(Path.GetDirectoryName(journal)!);
            File.WriteAllText(journal, saved.ToString());
            original = saved;
            try { write(false); }
            catch { original = null; File.Delete(journal); throw; }
        }
        else if (original is { } saved)
        {
            if (!read()) write(saved);
            original = null; File.Delete(journal);
        }
    }
    public void Dispose() => SetSuppressed(false);
}
