using System.Runtime.InteropServices;

namespace Bento.Windows;

public static class WindowAppearance
{
    [StructLayout(LayoutKind.Sequential)]
    private struct Margins { public int Left, Right, Top, Bottom; }
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(nint hwnd, int attribute, ref int value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmExtendFrameIntoClientArea(nint hwnd, ref Margins margins);

    public static void SetDarkCaption(nint hwnd, bool dark)
    {
        int value = dark ? 1 : 0;
        DwmSetWindowAttribute(hwnd, 20, ref value, sizeof(int));
    }
    public static bool SetAcrylic(nint hwnd, bool dark)
    {
        SetDarkCaption(hwnd, dark);
        int corners = 2, backdrop = 3; // Rounded corners; transient desktop acrylic, Windows 11 22H2+.
        DwmSetWindowAttribute(hwnd, 33, ref corners, sizeof(int));
        var margins = new Margins { Left = -1, Right = -1, Top = -1, Bottom = -1 };
        return DwmExtendFrameIntoClientArea(hwnd, ref margins) >= 0 &&
            DwmSetWindowAttribute(hwnd, 38, ref backdrop, sizeof(int)) >= 0;
    }
    public static void ClearBackdrop(nint hwnd)
    {
        int none = 1;
        DwmSetWindowAttribute(hwnd, 38, ref none, sizeof(int));
        var margins = new Margins();
        DwmExtendFrameIntoClientArea(hwnd, ref margins);
    }
}
