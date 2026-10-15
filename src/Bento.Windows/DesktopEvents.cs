using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Bento.Windows;

public sealed class DesktopEvents : IDisposable
{
    private readonly Native.WinEventProc callback;
    private readonly nint hook;
    public event Action<long, bool>? NativeDrag;
    public DesktopEvents()
    {
        callback = (_, type, hwnd, _, _, _, _) =>
        {
            if (hwnd != 0) NativeDrag?.Invoke(hwnd.ToInt64(), type == 0x000A);
        };
        hook = Native.SetWinEventHook(0x000A, 0x000B, 0, callback, 0, 0, 2);
        if (hook == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to watch window drags.");
    }
    public void Dispose() { if (hook != 0) Native.UnhookWinEvent(hook); GC.KeepAlive(callback); }
}

public static class DesktopIntegration
{
    public const uint ModAlt = 1, ModControl = 2, ModShift = 4, ModWin = 8;
    public static bool RegisterShortcut(nint hwnd, int id, uint modifiers, uint key) => Native.RegisterHotKey(hwnd, id, modifiers | 0x4000, key);
    public static int ShortcutError => Marshal.GetLastPInvokeError();
    public static void UnregisterShortcut(nint hwnd, int id) => Native.UnregisterHotKey(hwnd, id);
    public static void ConfigureOverlay(nint hwnd, bool passThrough)
    {
        long style = Native.GetWindowLongPtr(hwnd, -20).ToInt64();
        style |= 0x08000080; // No activation; tool window stays out of Alt+Tab.
        style = passThrough ? style | 0x20 : style & ~0x20L;
        Native.SetWindowLongPtr(hwnd, -20, (nint)style);
    }
    public static void PositionOverlay(nint hwnd, Bento.Core.PixelRect bounds) =>
        Native.SetWindowPos(hwnd, new nint(-1), bounds.X, bounds.Y, bounds.Width, bounds.Height, 0x0010);
}
