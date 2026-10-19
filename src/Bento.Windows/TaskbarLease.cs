using System.Runtime.InteropServices;
using System.Text.Json;
using Bento.Core;

namespace Bento.Windows;

// The shell owns taskbar presentation. Request autohide through its documented
// appbar API; never hide shell windows or rewrite Explorer's registry blobs.
public sealed class TaskbarLease : IDisposable
{
    private readonly OwnedBitLease lease;
    public TaskbarLease(string journal, Func<uint>? read = null, Action<uint>? write = null)
    {
        BitLeaseRecord? recovery = null;
        if (File.Exists(journal)) recovery = JsonSerializer.Deserialize<BitLeaseRecord>(File.ReadAllText(journal))
            ?? throw new InvalidDataException("The taskbar recovery journal is invalid.");
        void Persist(BitLeaseRecord? entry)
        {
            if (entry is null) { if (File.Exists(journal)) File.Delete(journal); return; }
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(journal))!);
            using (var stream = new FileStream(journal + ".tmp", FileMode.Create, FileAccess.Write, FileShare.None))
            { JsonSerializer.Serialize(stream, entry); stream.Flush(flushToDisk: true); }
            File.Move(journal + ".tmp", journal, true);
        }
        lease = new(1, read ?? ReadState, write ?? WriteState, Persist, recovery);
    }
    public bool Superseded => lease.Superseded;
    public void SetHidden(bool hidden) => lease.Set(hidden);
    public void Dispose() => lease.Dispose();
    private static uint ReadState()
    {
        var data = new AppBarData { Size = (uint)Marshal.SizeOf<AppBarData>() };
        return (uint)SHAppBarMessage(4, ref data).ToUInt64();
    }
    private static void WriteState(uint state)
    {
        var taskbar = FindWindow("Shell_TrayWnd", null);
        if (taskbar == 0) throw new InvalidOperationException("The Windows taskbar is unavailable.");
        var data = new AppBarData { Size = (uint)Marshal.SizeOf<AppBarData>(), Window = taskbar, Parameter = (nint)state };
        SHAppBarMessage(10, ref data); // ABM_SETSTATE always returns TRUE; OwnedBitLease verifies by reading back.
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct AppBarData { public uint Size; public nint Window; public uint Callback, Edge; public Native.Rect Rect; public nint Parameter; }
    [DllImport("shell32.dll")] private static extern nuint SHAppBarMessage(uint message, ref AppBarData data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern nint FindWindow(string className, string? title);
}
