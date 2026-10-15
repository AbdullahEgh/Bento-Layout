using System.Runtime.InteropServices;
using Bento.Core;

namespace Bento.Windows;

public sealed class WindowThumbnail : IDisposable
{
    private nint thumbnail;
    public WindowThumbnail(nint destination, long source)
    {
        Marshal.ThrowExceptionForHR(Register(destination, (nint)source, out thumbnail));
    }
    public void Update(int width, int height)
    {
        var properties = new Properties { Flags = 1 | 4 | 8 | 16, Destination = new Native.Rect { Right = width, Bottom = height },
            Opacity = 255, Visible = true, SourceClientAreaOnly = false };
        Marshal.ThrowExceptionForHR(UpdateProperties(thumbnail, ref properties));
    }
    public void Dispose() { if (thumbnail != 0) { Unregister(thumbnail); thumbnail = 0; } }
    [StructLayout(LayoutKind.Sequential)] private struct Properties
    {
        public uint Flags;
        public Native.Rect Destination, Source;
        public byte Opacity;
        [MarshalAs(UnmanagedType.Bool)] public bool Visible;
        [MarshalAs(UnmanagedType.Bool)] public bool SourceClientAreaOnly;
    }
    [DllImport("dwmapi.dll", EntryPoint = "DwmRegisterThumbnail")] private static extern int Register(nint destination, nint source, out nint thumbnail);
    [DllImport("dwmapi.dll", EntryPoint = "DwmUpdateThumbnailProperties")] private static extern int UpdateProperties(nint thumbnail, ref Properties properties);
    [DllImport("dwmapi.dll", EntryPoint = "DwmUnregisterThumbnail")] private static extern int Unregister(nint thumbnail);
}
