using System.ComponentModel;
using System.Runtime.InteropServices;
using Bento.Core;

namespace Bento.Windows;

// Observe presses without consuming or reinjecting input. The real application
// receives the original first click, even when it was already foreground.
public sealed class PointerObserver : IDisposable
{
    private readonly Hook callback;
    private nint handle;
    public event Action<PixelPoint>? Pressed;
    public PointerObserver()
    {
        callback = (code, message, data) =>
        {
            try
            {
                if (code >= 0 && message.ToInt64() is 0x0201 or 0x0204 or 0x0207)
                {
                    var value = Marshal.PtrToStructure<MouseData>(data);
                    Pressed?.Invoke(new(value.Point.X, value.Point.Y));
                }
            }
            catch { /* Never propagate a managed exception into the input hook. */ }
            return CallNextHookEx(handle, code, message, data);
        };
        handle = SetWindowsHookEx(14, callback, GetModuleHandle(null), 0);
        if (handle == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not observe paused-window clicks.");
    }
    public void Dispose() { if (handle != 0) { UnhookWindowsHookEx(handle); handle = 0; } GC.KeepAlive(callback); }
    private delegate nint Hook(int code, nint message, nint data);
    [StructLayout(LayoutKind.Sequential)] private struct MouseData { public Native.Point Point; public uint Mouse, Flags, Time; public nuint Extra; }
    [DllImport("user32.dll", SetLastError = true)] private static extern nint SetWindowsHookEx(int type, Hook callback, nint module, uint thread);
    [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(nint handle);
    [DllImport("user32.dll")] private static extern nint CallNextHookEx(nint handle, int code, nint message, nint data);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern nint GetModuleHandle(string? module);
}
