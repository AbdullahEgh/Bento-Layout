using Microsoft.Win32;
using System.Diagnostics;
using System.Security;

namespace Bento.Windows;

public static class ShellDesktopIdentity
{
    private const string Explorer = @"Software\Microsoft\Windows\CurrentVersion\Explorer\";

    // Explorer persists the current desktop here; PowerToys FancyZones uses these
    // same two locations. No foreground HWND inference, registry writes, or
    // guessed first desktop when more than one desktop exists.
    // https://github.com/microsoft/PowerToys/blob/main/src/modules/fancyzones/FancyZonesLib/VirtualDesktop.cpp
    public static Guid? Read()
    {
        try
        {
            using var modern = Registry.CurrentUser.OpenSubKey(Explorer + "VirtualDesktops", writable: false);
            using var process = Process.GetCurrentProcess();
            using var session = Registry.CurrentUser.OpenSubKey(Explorer + $@"SessionInfo\{process.SessionId}\VirtualDesktops", writable: false);
            return Resolve(modern?.GetValue("CurrentVirtualDesktop"), session?.GetValue("CurrentVirtualDesktop"), modern?.GetValue("VirtualDesktopIDs"));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or SecurityException)
        { return null; } // Retry next sample; never retain a stale successful identity.
    }

    public static Guid? Resolve(object? current, object? sessionCurrent, object? desktops)
    {
        static Guid? Parse(object? value) => value is byte[] { Length: 16 } bytes && new Guid(bytes) is var id && id != Guid.Empty ? id : null;
        if (Parse(current) is { } modern) return modern;
        if (Parse(sessionCurrent) is { } session) return session;
        // Before the first desktop switch Explorer can omit CurrentVirtualDesktop.
        // Exactly one complete ID is unambiguous; a longer list is not.
        return current is null && sessionCurrent is null ? Parse(desktops) : null;
    }
}
