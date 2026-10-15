using System.Runtime.InteropServices;
using System.Text;

namespace Bento.Windows;

internal static class Native
{
    internal delegate bool EnumWindowProc(nint hwnd, nint data);
    internal delegate bool MonitorProc(nint monitor, nint dc, ref Rect rect, nint data);
    internal delegate void WinEventProc(nint hook, uint eventType, nint hwnd, int objectId, int childId, uint thread, uint time);
    [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] internal struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] internal struct MinMaxInfo
    { public Point Reserved, MaxSize, MaxPosition, MinTrack, MaxTrack; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] internal struct MonitorInfo
    {
        public int Size;
        public Rect Monitor, Work;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Device;
    }
    [StructLayout(LayoutKind.Sequential)] internal struct WindowPlacement
    { public int Length, Flags, ShowCommand; public Point MinPosition, MaxPosition; public Rect NormalPosition; }
    [DllImport("user32.dll")] internal static extern bool EnumWindows(EnumWindowProc callback, nint data);
    [DllImport("user32.dll")] internal static extern bool IsWindow(nint hwnd);
    [DllImport("user32.dll")] internal static extern bool IsWindowVisible(nint hwnd);
    [DllImport("user32.dll")] internal static extern bool IsIconic(nint hwnd);
    [DllImport("user32.dll")] internal static extern bool ShowWindow(nint hwnd, int command);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern int GetWindowText(nint hwnd, StringBuilder text, int count);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern int GetClassName(nint hwnd, StringBuilder text, int count);
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(nint hwnd, out uint processId);
    [DllImport("user32.dll")] internal static extern nint GetWindow(nint hwnd, uint command);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] internal static extern nint GetWindowLongPtr(nint hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)] internal static extern nint SetWindowLongPtr(nint hwnd, int index, nint value);
    [DllImport("user32.dll", SetLastError = true)] internal static extern bool GetWindowRect(nint hwnd, out Rect rect);
    [DllImport("user32.dll", SetLastError = true)] internal static extern bool SetWindowPos(nint hwnd, nint after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] internal static extern bool GetWindowPlacement(nint hwnd, ref WindowPlacement placement);
    [DllImport("user32.dll")] internal static extern bool SetWindowPlacement(nint hwnd, in WindowPlacement placement);
    [DllImport("user32.dll")] internal static extern bool EnumDisplayMonitors(nint dc, nint clip, MonitorProc callback, nint data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo info);
    [DllImport("shcore.dll")] internal static extern int GetDpiForMonitor(nint monitor, int type, out uint x, out uint y);
    [DllImport("user32.dll")] internal static extern uint GetDpiForWindow(nint hwnd);
    [DllImport("user32.dll")] internal static extern nint MonitorFromWindow(nint hwnd, uint flags);
    [DllImport("user32.dll")] internal static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] internal static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] internal static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll", SetLastError = true)] internal static extern bool RegisterHotKey(nint hwnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] internal static extern bool UnregisterHotKey(nint hwnd, int id);
    [DllImport("user32.dll")] internal static extern nint SetWinEventHook(uint min, uint max, nint module, WinEventProc callback, uint process, uint thread, uint flags);
    [DllImport("user32.dll")] internal static extern bool UnhookWinEvent(nint hook);
    [DllImport("user32.dll", SetLastError = true)] internal static extern nint SendMessageTimeout(nint hwnd, uint message, nint wparam, nint lparam, uint flags, uint timeout, out nint result);
    [DllImport("dwmapi.dll")] internal static extern int DwmGetWindowAttribute(nint hwnd, uint attribute, out Rect value, int size);
    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")] internal static extern int DwmGetIntAttribute(nint hwnd, uint attribute, out int value, int size);
}
