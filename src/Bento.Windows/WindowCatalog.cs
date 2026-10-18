using System.Runtime.InteropServices;
using System.Text;
using Bento.Core;

namespace Bento.Windows;

public sealed record AppWindow(long Id, uint ProcessId, string Title, PixelSize Minimum, string MonitorId = "", double DpiScale = 1, PixelSize? ReportedMinimum = null);
public sealed record DesktopMonitor(string Id, PixelRect WorkArea, double Scale, PixelRect? ScreenBounds = null)
{
    public PixelRect Bounds => ScreenBounds ?? WorkArea;
}

public static class WindowCatalog
{
    public static IReadOnlyList<AppWindow> Discover(bool includeMinimized = true, IReadOnlyDictionary<long, AppWindow>? cache = null)
    {
        var windows = new List<AppWindow>();
        var systemProcesses = new Dictionary<uint, bool>();
        Native.EnumWindows((handle, _) =>
        {
            Native.GetWindowThreadProcessId(handle, out var process);
            long style = Native.GetWindowLongPtr(handle, -20).ToInt64();
            long regularStyle = Native.GetWindowLongPtr(handle, -16).ToInt64();
            if (!systemProcesses.TryGetValue(process, out bool system))
            {
                try { using var app = System.Diagnostics.Process.GetProcessById((int)process); system = app.ProcessName == "SystemSettings"; }
                catch (Exception ex) when (ex is ArgumentException or System.ComponentModel.Win32Exception) { system = false; }
                systemProcesses[process] = system;
            }
            if (process == Environment.ProcessId || system || (style & 8) != 0 || !Native.IsWindowVisible(handle) ||
                (!includeMinimized && Native.IsIconic(handle)) ||
                (style & 0x80) != 0 || (style & 0x08000000) != 0 || (regularStyle & 0x40000000) != 0 ||
                (Native.GetWindow(handle, 4) != 0 && (style & 0x40000) == 0)) return true;
            if (Native.DwmGetIntAttribute(handle, 14, out int cloaked, sizeof(int)) == 0 && cloaked != 0) return true;
            var title = new StringBuilder(512);
            Native.GetWindowText(handle, title, title.Capacity);
            if (string.IsNullOrWhiteSpace(title.ToString())) return true;
            var className = new StringBuilder(256);
            Native.GetClassName(handle, className, className.Capacity);
            if (className.ToString() is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd") return true;
            var monitor = new Native.MonitorInfo { Size = Marshal.SizeOf<Native.MonitorInfo>(), Device = "" };
            Native.GetMonitorInfo(Native.MonitorFromWindow(handle, 2), ref monitor);
            double scale = WindowScale(handle.ToInt64());
            var minimum = cache is not null && cache.TryGetValue(handle.ToInt64(), out var known) && known.ProcessId == process
                ? new PixelSize((int)Math.Ceiling((known.ReportedMinimum ?? known.Minimum).Width * scale / known.DpiScale),
                    (int)Math.Ceiling((known.ReportedMinimum ?? known.Minimum).Height * scale / known.DpiScale)) : ReadMinimum(handle);
            windows.Add(new(handle.ToInt64(), process, title.ToString(), minimum, monitor.Device, scale, minimum));
            return true;
        }, 0);
        return windows;
    }

    private static PixelSize ReadMinimum(nint handle)
    {
        double scale = Math.Max(96, Native.GetDpiForWindow(handle)) / 96d;
        var info = new Native.MinMaxInfo();
        nint memory = Marshal.AllocHGlobal(Marshal.SizeOf<Native.MinMaxInfo>());
        try
        {
            Marshal.StructureToPtr(info, memory, false);
            // Bounded cross-process system message. A hung application must not stall discovery.
            if (Native.SendMessageTimeout(handle, 0x24, 0, memory, 0x22, 40, out _) != 0)
                info = Marshal.PtrToStructure<Native.MinMaxInfo>(memory);
        }
        finally { Marshal.FreeHGlobal(memory); }
        return new(Math.Max((int)(180 * scale), info.MinTrack.X), Math.Max((int)(120 * scale), info.MinTrack.Y));
    }

    public static IReadOnlyList<DesktopMonitor> Monitors()
    {
        var monitors = new List<DesktopMonitor>();
        Native.EnumDisplayMonitors(0, 0, (nint handle, nint dc, ref Native.Rect rect, nint data) =>
        {
            var info = new Native.MonitorInfo { Size = Marshal.SizeOf<Native.MonitorInfo>(), Device = "" };
            if (Native.GetMonitorInfo(handle, ref info))
            {
                Native.GetDpiForMonitor(handle, 0, out uint x, out _);
                monitors.Add(new(info.Device, Geometry.FromNative(info.Work), Math.Max(96, x) / 96d, Geometry.FromNative(info.Monitor)));
            }
            return true;
        }, 0);
        return monitors;
    }
    public static long Foreground => Native.GetForegroundWindow().ToInt64();
    public static double WindowScale(long id) => Math.Max(96, Native.GetDpiForWindow((nint)id)) / 96d;
    public static bool Exists(long id) => Native.IsWindow((nint)id);
    public static bool HasCaption(long id) => (Native.GetWindowLongPtr((nint)id, -16).ToInt64() & 0x00C00000) != 0;
    public static bool IsMaximized(long id)
    {
        var placement = new Native.WindowPlacement { Length = Marshal.SizeOf<Native.WindowPlacement>() };
        return Native.GetWindowPlacement((nint)id, ref placement) && placement.ShowCommand == 3;
    }
    public static PixelRect? ScreenBounds(long id)
    {
        var info = new Native.MonitorInfo { Size = Marshal.SizeOf<Native.MonitorInfo>(), Device = "" };
        return Native.GetMonitorInfo(Native.MonitorFromWindow((nint)id, 2), ref info) ? Geometry.FromNative(info.Monitor) : null;
    }
    public static bool IsVisible(long id) => Native.IsWindowVisible((nint)id);
    public static bool IsCloaked(long id) => Native.DwmGetIntAttribute((nint)id, 14, out int cloaked, sizeof(int)) == 0 && cloaked != 0;
    public static uint ProcessId(long id) { Native.GetWindowThreadProcessId((nint)id, out uint process); return process; }
    public static bool IsMinimized(long id) => Native.IsIconic((nint)id);
    public static PixelPoint Cursor { get { Native.GetCursorPos(out var point); return new(point.X, point.Y); } }
    public static bool EscapeDown => (Native.GetAsyncKeyState(0x1B) & 0x8000) != 0;
    public static bool LeftButtonDown => (Native.GetAsyncKeyState(1) & 0x8000) != 0;
}

public static class Geometry
{
    internal static PixelRect FromNative(Native.Rect rect) => new(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top);
    public static PixelRect CompensateFrame(PixelRect desired, PixelRect outer, PixelRect visible) => new(
        desired.X - (visible.X - outer.X), desired.Y - (visible.Y - outer.Y),
        desired.Width + outer.Width - visible.Width, desired.Height + outer.Height - visible.Height);
}
