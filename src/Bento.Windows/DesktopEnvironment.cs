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

// Read Explorer's current desktop identity; helper/tool HWNDs need not belong to a shell desktop.
public sealed class DesktopEnvironment : IDesktopEnvironment
{
    [ComImport, Guid("A5CD92FF-29BE-454C-8D04-D82879FB3F1B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IVirtualDesktopManager
    {
        [PreserveSig] int IsWindowOnCurrentVirtualDesktop(nint window, [MarshalAs(UnmanagedType.Bool)] out bool current);
        [PreserveSig] int GetWindowDesktopId(nint window, out Guid desktop);
        [PreserveSig] int MoveWindowToDesktop(nint window, in Guid desktop);
    }
    private readonly Func<Guid?> readIdentity;
    public DesktopEnvironment(Func<Guid?>? readIdentity = null) => this.readIdentity = readIdentity ?? ShellDesktopIdentity.Read;
    private IVirtualDesktopManager? manager;
    private Guid? identity;
    private bool disposed;
    private bool suspended;
    public DesktopObservation Sample()
    {
        if (disposed) return new(null, true, "Windows desktop integration is closed.");
        try
        {
            manager ??= (IVirtualDesktopManager)(Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("AA509086-5CA9-4C25-8F95-589D3C07B48A"), throwOnError: true)!)
                ?? throw new InvalidOperationException("Virtual desktop manager is unavailable."));
            bool locked = !InteractiveDesktop();
            bool overview = ShellOverview();
            suspended = locked || overview;
            if (suspended) return new(identity, true, locked ? "Session locked or not present." : "Desktop overview or shell transition.");
            identity = readIdentity();
            suspended = identity is null || identity == Guid.Empty;
            return new(identity, suspended, suspended ? "Windows did not identify the current desktop; arrangement deferred." : null);
        }
        catch (Exception ex) when (ex is COMException or InvalidCastException or TypeLoadException)
        {
            // Explorer can restart. Retry the connection on a later sample.
            ReleaseManager(); identity = null; suspended = true;
            return new(null, true, "Windows desktop integration is unavailable; arrangement deferred.");
        }
    }
    public bool IsCurrent(Guid desktop)
    {
        return !disposed && !suspended && desktop != Guid.Empty && identity == desktop && manager is not null &&
            InteractiveDesktop() && !ShellOverview() && readIdentity() == desktop;
    }
    public bool Contains(Guid desktop, long window)
    {
        if (!IsCurrent(desktop)) return false;
        try
        {
            int presentResult = manager!.IsWindowOnCurrentVirtualDesktop((nint)window, out bool current);
            int ownerResult = manager.GetWindowDesktopId((nint)window, out Guid owner);
            if (presentResult < 0 || ownerResult < 0) { ReleaseManager(); suspended = true; return false; }
            return current && owner == desktop && IsCurrent(desktop);
        }
        catch (COMException) { ReleaseManager(); suspended = true; return false; }
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
        disposed = true; suspended = true; identity = null;
        ReleaseManager();
    }
    private void ReleaseManager()
    {
        var connection = manager; manager = null;
        if (connection is not null)
            try { Marshal.FinalReleaseComObject(connection); } catch (InvalidComObjectException) { /* Explorer already disconnected. */ }
    }
    // Notification availability is not session-lock state (it also includes idle
    // and presentation modes). Query the actual input desktop on every sample.
    private static bool InteractiveDesktop()
    {
        nint desktop = OpenInputDesktop(0, false, 0x0001); // DESKTOP_READOBJECTS
        if (desktop == 0) return false;
        try
        {
            var name = new StringBuilder(256);
            return GetUserObjectInformation(desktop, 2, name, name.Capacity * sizeof(char), out _) &&
                string.Equals(name.ToString(), "Default", StringComparison.OrdinalIgnoreCase);
        }
        finally { CloseDesktop(desktop); }
    }
    [DllImport("user32.dll", SetLastError = true)] private static extern nint OpenInputDesktop(uint flags, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint access);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetUserObjectInformation(nint handle, int index, StringBuilder value, int length, out int needed);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CloseDesktop(nint desktop);
}
