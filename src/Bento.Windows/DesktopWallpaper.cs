using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;
using Bento.Core;

namespace Bento.Windows;

public sealed record WallpaperInfo(string Path, PixelRect Monitor, PixelRect Desktop, int Position, uint Background);

public static class DesktopWallpaper
{
    public static WallpaperInfo? At(PixelPoint point)
    {
        var fallback = LegacyAt(point);
        IDesktopWallpaper? wallpaper = null;
        try
        {
            wallpaper = (IDesktopWallpaper)Activator.CreateInstance(Type.GetTypeFromCLSID(new("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD"))!)!;
            uint count = wallpaper.GetMonitorDevicePathCount();
            string? selected = null;
            PixelRect monitor = default, desktop = default;
            for (uint i = 0; i < count; i++)
            {
                string id = wallpaper.GetMonitorDevicePathAt(i);
                var r = wallpaper.GetMonitorRECT(id);
                var bounds = new PixelRect(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
                desktop = i == 0 ? bounds : Union(desktop, bounds);
                if (bounds.Contains(point)) { selected = id; monitor = bounds; }
            }
            if (selected is null) return fallback;
            // Some virtual displays expose their geometry but reject individual wallpaper getters.
            // Preserve per-monitor data when available, falling back independently for each property.
            return new(Read(() => wallpaper.GetWallpaper(selected), fallback?.Path ?? ""), monitor, desktop,
                Read(wallpaper.GetPosition, fallback?.Position ?? 4), Read(wallpaper.GetBackgroundColor, GetSysColor(1)));
        }
        catch (COMException) { return fallback; }
        finally { if (wallpaper is not null) Marshal.ReleaseComObject(wallpaper); }
    }
    private static T Read<T>(Func<T> get, T fallback) { try { return get(); } catch (COMException) { return fallback; } }
    private static PixelRect Union(PixelRect a, PixelRect b)
    {
        int x = Math.Min(a.X, b.X), y = Math.Min(a.Y, b.Y);
        return new(x, y, Math.Max(a.Right, b.Right) - x, Math.Max(a.Bottom, b.Bottom) - y);
    }
    private static WallpaperInfo? LegacyAt(PixelPoint point)
    {
        PixelRect? monitor = null, desktop = null;
        Native.EnumDisplayMonitors(0, 0, (nint handle, nint dc, ref Native.Rect rect, nint data) =>
        {
            var bounds = new PixelRect(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top);
            desktop = desktop is null ? bounds : Union(desktop.Value, bounds);
            if (bounds.Contains(point)) monitor = bounds;
            return true;
        }, 0);
        if (monitor is null || desktop is null) return null;
        var path = new StringBuilder(32768);
        SystemParametersInfo(0x0073, (uint)path.Capacity, path, 0);
        using var key = Registry.CurrentUser.OpenSubKey(@"Control Panel\Desktop");
        string style = Convert.ToString(key?.GetValue("WallpaperStyle")) ?? "10";
        int position = Convert.ToString(key?.GetValue("TileWallpaper")) == "1" ? 1 : style switch
        { "0" => 0, "2" => 2, "6" => 3, "22" => 5, _ => 4 };
        return new(path.ToString(), monitor.Value, desktop.Value, position, GetSysColor(1));
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool SystemParametersInfo(uint action, uint size, StringBuilder value, uint flags);
    [DllImport("user32.dll")] private static extern uint GetSysColor(int index);
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    // IUnknown vtable order from shobjidl_core.h. Only the initial methods are needed.
    [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDesktopWallpaper
    {
        void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitor, [MarshalAs(UnmanagedType.LPWStr)] string path);
        [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitor);
        [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint index);
        uint GetMonitorDevicePathCount();
        Rect GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitor);
        void SetBackgroundColor(uint color);
        uint GetBackgroundColor();
        void SetPosition(int position);
        int GetPosition();
    }
}
