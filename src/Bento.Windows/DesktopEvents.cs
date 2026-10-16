using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Bento.Windows;

public sealed class DesktopEvents : IDisposable
{
    private readonly Native.WinEventProc callback;
    private readonly nint hook;
    private readonly nint foregroundHook;
    public event Action<long, bool>? NativeDrag;
    public event Action? ForegroundChanged;
    public DesktopEvents()
    {
        callback = (_, type, hwnd, _, _, _, _) =>
        {
            if (type == 3) { ForegroundChanged?.Invoke(); return; }
            if (hwnd != 0) NativeDrag?.Invoke(hwnd.ToInt64(), type == 0x000A);
        };
        hook = Native.SetWinEventHook(0x000A, 0x000B, 0, callback, 0, 0, 2);
        if (hook == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to watch window drags.");
        foregroundHook = Native.SetWinEventHook(3, 3, 0, callback, 0, 0, 2);
    }
    public void Dispose() { if (hook != 0) Native.UnhookWinEvent(hook); if (foregroundHook != 0) Native.UnhookWinEvent(foregroundHook); GC.KeepAlive(callback); }
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
    public static void PositionOverlay(nint hwnd, Bento.Core.PixelRect bounds, bool topmost = true) =>
        Native.SetWindowPos(hwnd, new nint(topmost ? -1 : -2), bounds.X, bounds.Y, bounds.Width, bounds.Height, 0x0010);
    public static void MoveOverlay(nint hwnd, Bento.Core.PixelRect bounds) =>
        Native.SetWindowPos(hwnd, 0, bounds.X, bounds.Y, bounds.Width, bounds.Height, 0x0014); // NOZORDER | NOACTIVATE
    public static void PlaceBelow(nint hwnd, nint sibling) => Native.SetWindowPos(hwnd, sibling, 0, 0, 0, 0, 0x0013);
    public static void RaiseOverlay(nint hwnd)
    {
        // A background process cannot reliably raise HWND_TOP above the foreground
        // app. Promote then immediately demote, without activation or a permanent
        // topmost flag; settings can still precede the input surfaces.
        Native.SetWindowPos(hwnd, new nint(-1), 0, 0, 0, 0, 0x0013);
        Native.SetWindowPos(hwnd, new nint(-2), 0, 0, 0, 0, 0x0013);
    }
    public static void PlaceBehindApplications(nint hwnd, IReadOnlyCollection<long> applications)
    {
        var ids = applications.ToHashSet();
        nint lowest = 0;
        Native.EnumWindows((window, _) => { if (ids.Contains(window.ToInt64()) && Native.IsWindowVisible(window) && !Native.IsIconic(window)) lowest = window; return true; }, 0);
        if (lowest != 0) PlaceBelow(hwnd, lowest);
    }
}
