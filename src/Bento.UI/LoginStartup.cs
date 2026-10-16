using Microsoft.Win32;

namespace Bento.UI;

public static class LoginStartup
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Bento";
    private static string Command
    {
        get
        {
            string executable = Path.Combine(AppContext.BaseDirectory, "Bento.exe");
            if (!File.Exists(executable)) throw new FileNotFoundException("Keep Bento.exe in its installation folder before enabling Start at login.", executable);
            // A quoted executable path is required for portable installations with spaces.
            return $"\"{executable}\" --login";
        }
    }
    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            string? current = key?.GetValue(ValueName) as string;
            return current is not null && string.Equals(current, Command, StringComparison.OrdinalIgnoreCase);
        }
    }
    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey, writable: true);
        if (enabled) key.SetValue(ValueName, Command, RegistryValueKind.String);
        else key.DeleteValue(ValueName, throwOnMissingValue: false);
    }
}
