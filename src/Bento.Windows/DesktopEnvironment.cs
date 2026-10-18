using System.Runtime.InteropServices;
using System.Text;
using Bento.Core;

namespace Bento.Windows;

public sealed record DesktopObservation(Guid? Desktop, bool Suspended, string? Reason = null);
public interface IDesktopEnvironment : IDisposable
{
    DesktopObservation Sample();
    bool IsCurrent(Guid desktop);
    bool Contains(Guid desktop, long window);
    bool Fullscreen(long window);
    bool MoveHelper(long helper, Guid desktop);
}

// An ownerless, invisible probe obtains an actual shell desktop GUID. We verify
// both the GUID and current membership; failure defers writes rather than using
// the foreground app's home desktop (which can be pinned on all desktops).
public sealed class DesktopEnvironment : IDesktopEnvironment
{
    [ComImport, Guid("A5CD92FF-29BE-454C-8D04-D82879FB3F1B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IVirtualDesktopManager
    {
        [PreserveSig] int IsWindowOnCurrentVirtualDesktop(nint window, [MarshalAs(UnmanagedType.Bool)] out bool current);
        [PreserveSig] int GetWindowDesktopId(nint window, out Guid desktop);
        [PreserveSig] int MoveWindowToDesktop(nint window, in Guid desktop);
    }
    private IVirtualDesktopManager? manager;
    private nint probe;
    private Guid? identity;
    private bool unavailable;
    private bool suspended;
    private long lastProbe;
    private bool ambiguousIdentity;
    public DesktopObservation Sample()
    {
        try
        {
            if (unavailable) return new(null, true, "Windows virtual desktop membership is unavailable.");
            manager ??= (IVirtualDesktopManager)(Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("AA509086-5CA9-4C25-8F95-589D3C07B48A"), throwOnError: true)!)
                ?? throw new InvalidOperationException("Virtual desktop manager is unavailable."));
            bool locked = SHQueryUserNotificationState(out int state) >= 0 && state == 1;
            bool overview = ShellOverview();
            suspended = locked || overview;
            if (suspended) return new(identity, true, locked ? "Session locked or not present." : "Desktop overview or shell transition.");
            bool oldCurrent = probe != 0 && manager.IsWindowOnCurrentVirtualDesktop(probe, out bool present) >= 0 && present;
            long now = Environment.TickCount64;
            if (identity is null || !oldCurrent || ambiguousIdentity || now - lastProbe >= 250)
            {
                // Recheck with a fresh ownerless probe. A reused window can be
                // pinned to every desktop and its home GUID is then insufficient.
                nint fresh = CreateWindowEx(0x00080000 | 0x08000000 | 0x00000080 | 0x00000020,
                    "STATIC", "Bento desktop identity", unchecked((int)0x80000000), -32000, -32000, 1, 1, 0, 0, 0, 0);
                if (fresh == 0) { suspended = true; return new(null, true, "Could not identify the current Windows desktop."); }
                SetLayeredWindowAttributes(fresh, 0, 0, 2); Native.ShowWindow(fresh, 4);
                if (manager.GetWindowDesktopId(fresh, out Guid id) < 0 || id == Guid.Empty ||
                    manager.IsWindowOnCurrentVirtualDesktop(fresh, out bool current) < 0 || !current)
                {
                    DestroyWindow(fresh); suspended = true;
                    return new(null, true, "Windows did not identify the current desktop; arrangement deferred.");
                }
                if (identity is { } previous && previous != id && oldCurrent)
                {
                    DestroyWindow(fresh); suspended = true; ambiguousIdentity = true;
                    return new(null, true, "Shared or changing desktop identity. Wait for the shell, or unpin Bento from all desktops.");
                }
                if (probe != 0) DestroyWindow(probe);
                probe = fresh; identity = id; lastProbe = now; ambiguousIdentity = false;
            }
            return new(identity, false);
        }
        catch (Exception ex) when (ex is COMException or InvalidCastException or TypeLoadException)
        { unavailable = true; return new(null, true, "Windows desktop integration is unavailable; arrangement deferred."); }
    }
    public bool IsCurrent(Guid desktop)
    {
        try { return !suspended && !(SHQueryUserNotificationState(out int state) >= 0 && state == 1) && !ShellOverview() && identity == desktop && manager is not null && probe != 0 &&
            manager.IsWindowOnCurrentVirtualDesktop(probe, out bool current) >= 0 && current; }
        catch (COMException) { return false; }
    }
    public bool Contains(Guid desktop, long window)
    {
        try { return IsCurrent(desktop) && manager!.IsWindowOnCurrentVirtualDesktop((nint)window, out bool current) >= 0 && current &&
            manager.GetWindowDesktopId((nint)window, out Guid owner) >= 0 && owner == desktop; }
        catch (COMException) { return false; }
    }
    public bool MoveHelper(long helper, Guid desktop)
    {
        // Only this process's helper windows may move, and only to the proven
        // current desktop. Never change user application desktop ownership.
        Native.GetWindowThreadProcessId((nint)helper, out uint process);
        if (process != Environment.ProcessId || !IsCurrent(desktop)) return false;
        try { return manager!.MoveWindowToDesktop((nint)helper, desktop) >= 0; }
        catch (COMException) { return false; }
    }
    public bool Fullscreen(long window)
    {
        var placement = new Native.WindowPlacement { Length = Marshal.SizeOf<Native.WindowPlacement>() };
        if (!Native.IsWindowVisible((nint)window) || Native.IsIconic((nint)window) ||
            !Native.GetWindowPlacement((nint)window, ref placement) || placement.ShowCommand == 3 || !Native.GetWindowRect((nint)window, out var bounds)) return false;
        var monitor = new Native.MonitorInfo { Size = Marshal.SizeOf<Native.MonitorInfo>(), Device = "" };
        if (!Native.GetMonitorInfo(Native.MonitorFromWindow((nint)window, 2), ref monitor)) return false;
        long style = Native.GetWindowLongPtr((nint)window, -16).ToInt64();
        return FullscreenGeometry.Borderless(Geometry.FromNative(bounds), Geometry.FromNative(monitor.Monitor), placement.ShowCommand == 3, (style & 0x00C00000) != 0);
    }
    private static bool ShellOverview()
    {
        var foreground = (nint)WindowCatalog.Foreground;
        if (foreground == 0 || !Native.IsWindowVisible(foreground)) return false;
        var className = new StringBuilder(256); Native.GetClassName(foreground, className, className.Capacity);
        bool shellClass = className.ToString() is "MultitaskingViewFrame" or "XamlExplorerHostIslandWindow" or "TaskSwitcherWnd";
        if (!shellClass) return false;
        Native.GetWindowThreadProcessId(foreground, out uint id);
        try
        {
            using var process = System.Diagnostics.Process.GetProcessById((int)id);
            return process.ProcessName is "explorer" or "ShellExperienceHost" or "StartMenuExperienceHost";
        }
        catch (Exception ex) when (ex is ArgumentException or System.ComponentModel.Win32Exception) { return true; }
    }
    public void Dispose()
    {
        if (probe != 0) { DestroyWindow(probe); probe = 0; }
        if (manager is not null) { Marshal.FinalReleaseComObject(manager); manager = null; }
        identity = null; unavailable = true;
    }
    [DllImport("shell32.dll")] private static extern int SHQueryUserNotificationState(out int state);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern nint CreateWindowEx(int extended, string className, string title, int style, int x, int y, int width, int height, nint parent, nint menu, nint instance, nint parameter);
    [DllImport("user32.dll")] private static extern bool SetLayeredWindowAttributes(nint window, uint key, byte alpha, uint flags);
    [DllImport("user32.dll")] private static extern bool DestroyWindow(nint window);
}
