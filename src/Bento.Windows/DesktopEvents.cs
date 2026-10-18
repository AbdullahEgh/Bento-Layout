using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Bento.Windows;

public sealed class DesktopEvents : IDisposable
{
    private readonly Native.WinEventProc callback;
    private readonly List<nint> hooks = new();
    private bool disposed;
    public event Action<Exception>? ObserverFailed;
    public event Action<long, bool>? NativeDrag;
    public event Action? ForegroundChanged;
    public event Action? WindowsChanged;
    public event Action<long>? WindowInvalidated;
    public event Action<bool>? OverviewChanged;
    public event Action? DesktopChanged;
    public DesktopEvents()
    {
        callback = (_, type, hwnd, objectId, childId, _, _) =>
        {
            if (disposed) return;
            try
            {
            if (type == 3) { ForegroundChanged?.Invoke(); return; }
            if (type is 0x14 or 0x15) { OverviewChanged?.Invoke(type == 0x14); return; }
            if (type == 0x20) { DesktopChanged?.Invoke(); return; }
            if (type is >= 0x8000 and <= 0x8003 && objectId == 0 && childId == 0)
            {
                if (type == 0x8001) { if (hwnd != 0) WindowInvalidated?.Invoke(hwnd.ToInt64()); return; }
                if (hwnd != 0 && ((Native.GetWindowLongPtr(hwnd, -20).ToInt64() & 0x08000080) != 0 || (Native.GetWindowLongPtr(hwnd, -16).ToInt64() & 0x40000000) != 0)) return;
                WindowsChanged?.Invoke(); return;
            }
            if (type is 0x16 or 0x17) { WindowsChanged?.Invoke(); return; }
            if (hwnd != 0 && type is 0xA or 0xB) NativeDrag?.Invoke(hwnd.ToInt64(), type == 0xA);
            }
            catch (Exception ex) { try { ObserverFailed?.Invoke(ex); } catch { /* Never unwind into Win32. */ } }
        };
        void Watch(uint first, uint last, uint flags = 0)
        {
            var hook = Native.SetWinEventHook(first, last, 0, callback, 0, 0, flags);
            if (hook == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to watch desktop changes.");
            hooks.Add(hook);
        }
        try
        {
            Watch(0xA, 0xB); Watch(3, 3); Watch(0x14, 0x17); Watch(0x20, 0x20);
            Watch(0x8000, 0x8003, 2); // Skip our own helper create/show/hide feedback.
        }
        catch { Dispose(); throw; }
    }
    public void Dispose()
    {
        if (disposed) return; disposed = true;
        foreach (var hook in hooks) Native.UnhookWinEvent(hook);
        hooks.Clear(); GC.KeepAlive(callback);
    }
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
    public static void PlaceAboveApplication(nint overlay, long application)
    {
        nint previous = Native.GetWindow((nint)application, 3); // GW_HWNDPREV
        if (previous == overlay) return;
        Native.SetWindowPos(overlay, previous, 0, 0, 0, 0, 0x0013);
    }
    public static long ApplicationAt(PixelPoint point, IReadOnlySet<long> members, IReadOnlySet<long> ignored)
    {
        long hit = 0;
        Native.EnumWindows((window, _) =>
        {
            long style = Native.GetWindowLongPtr(window, -20).ToInt64();
            if (ignored.Contains(window.ToInt64()) || (style & 0x80020) == 0x80020 || !Native.IsWindowVisible(window) || Native.IsIconic(window) ||
                WindowCatalog.IsCloaked(window.ToInt64()) || !Native.GetWindowRect(window, out var rect) || !Geometry.FromNative(rect).Contains(point)) return true;
            if (members.Contains(window.ToInt64())) hit = window.ToInt64();
            return false; // A floating app/dialog above a member blocks its hit.
        }, 0);
        return hit;
    }
    public static IReadOnlySet<long> AboveMembers(IReadOnlySet<long> candidates, IReadOnlySet<long> members)
    {
        var before = new HashSet<long>(); var result = new HashSet<long>();
        Native.EnumWindows((window, _) =>
        {
            long id = window.ToInt64();
            if (members.Contains(id)) result.UnionWith(before);
            if (candidates.Contains(id)) before.Add(id);
            return true;
        }, 0);
        return result;
    }
    public static void PlaceBehindApplications(nint hwnd, IReadOnlyCollection<long> applications)
    {
        var ids = applications.ToHashSet();
        nint lowest = 0;
        Native.EnumWindows((window, _) => { if (ids.Contains(window.ToInt64()) && Native.IsWindowVisible(window) && !Native.IsIconic(window) && !WindowCatalog.IsCloaked(window.ToInt64()) && !Native.IsIconic(window)) lowest = window; return true; }, 0);
        if (lowest != 0) PlaceBelow(hwnd, lowest);
    }
}
