using System.ComponentModel;
using System.Runtime.InteropServices;
using Bento.Core;

namespace Bento.Windows;

public sealed class WindowSnapshot
{
    internal Native.WindowPlacement Placement;
    internal PixelRect Bounds;
    public PixelRect VisibleBounds { get; internal init; }
    public long WindowId { get; internal init; }
    public uint ProcessId { get; internal init; }
}

public sealed class WindowController
{
    public bool IsResizeInteraction(long id, PixelPoint point)
    {
        nint coordinates = (nint)((point.Y & 0xffff) << 16 | (point.X & 0xffff));
        return Native.SendMessageTimeout((nint)id, 0x84, 0, coordinates, 0x22, 40, out var hit) != 0
            && hit.ToInt64() is >= 10 and <= 17; // WM_NCHITTEST, HTLEFT through HTBOTTOMRIGHT.
    }
    public void Minimize(long id)
    {
        if (!WindowCatalog.Exists(id)) throw new InvalidOperationException("The window has closed.");
        Native.ShowWindow((nint)id, 6);
    }
    public WindowSnapshot Capture(long id)
    {
        var placement = new Native.WindowPlacement { Length = Marshal.SizeOf<Native.WindowPlacement>() };
        if (!Native.GetWindowPlacement((nint)id, ref placement) || !Native.GetWindowRect((nint)id, out var bounds))
            throw new InvalidOperationException("The application window is no longer available.");
        Native.GetWindowThreadProcessId((nint)id, out uint processId);
        return new() { WindowId = id, ProcessId = processId, Placement = placement, Bounds = Geometry.FromNative(bounds), VisibleBounds = VisibleBounds(id) };
    }

    public void Restore(WindowSnapshot snapshot)
    {
        if (!WindowCatalog.Exists(snapshot.WindowId)) return;
        Native.GetWindowThreadProcessId((nint)snapshot.WindowId, out uint processId);
        if (processId != snapshot.ProcessId) return; // HWNDs can be recycled after a process exits.
        if (!Native.SetWindowPlacement((nint)snapshot.WindowId, snapshot.Placement))
            throw new InvalidOperationException("Windows denied restoring an application window.");
        if (snapshot.Placement.ShowCommand is not (2 or 3)) SetOuter(snapshot.WindowId, snapshot.Bounds);
    }

    public PixelRect VisibleBounds(long id)
    {
        if (Native.DwmGetWindowAttribute((nint)id, 9, out var frame, Marshal.SizeOf<Native.Rect>()) == 0)
            return Geometry.FromNative(frame);
        if (!Native.GetWindowRect((nint)id, out var rect)) throw new InvalidOperationException("The window has closed.");
        return Geometry.FromNative(rect);
    }

    public void Move(long id, PixelRect desired)
    {
        if (!WindowCatalog.Exists(id)) throw new InvalidOperationException("The window has closed.");
        var placement = new Native.WindowPlacement { Length = Marshal.SizeOf<Native.WindowPlacement>() };
        Native.GetWindowPlacement((nint)id, ref placement);
        if (placement.ShowCommand is 2 or 3)
        {
            placement.ShowCommand = 4; // SW_SHOWNOACTIVATE: restore without stealing focus.
            if (!Native.SetWindowPlacement((nint)id, placement)) throw new InvalidOperationException("Windows denied restoring the window.");
        }
        if (!Native.GetWindowRect((nint)id, out var rect)) throw new InvalidOperationException("The window has closed.");
        uint previousDpi = Native.GetDpiForWindow((nint)id);
        SetOuter(id, Geometry.CompensateFrame(desired, Geometry.FromNative(rect), VisibleBounds(id)));
        if (Native.GetDpiForWindow((nint)id) != previousDpi && Native.GetWindowRect((nint)id, out rect))
            SetOuter(id, Geometry.CompensateFrame(desired, Geometry.FromNative(rect), VisibleBounds(id)));
        var actual = VisibleBounds(id);
        if (Math.Abs(actual.X - desired.X) > 2 || Math.Abs(actual.Y - desired.Y) > 2 ||
            Math.Abs(actual.Width - desired.Width) > 2 || Math.Abs(actual.Height - desired.Height) > 2)
            throw new InvalidOperationException("The application did not accept this size. Try a larger region.");
    }

    private static void SetOuter(long id, PixelRect rect)
    {
        if (!Native.SetWindowPos((nint)id, 0, rect.X, rect.Y, rect.Width, rect.Height, 0x0014))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Windows denied moving an application. Elevated apps may require Bento to run at the same privilege level.");
    }
}
