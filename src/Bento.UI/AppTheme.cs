using Microsoft.Win32;

namespace Bento.UI;

public static class AppTheme
{
    public static bool SystemDark => Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) is int value && value == 0;
    public static bool IsDark { get; private set; }
    public static event Action? Changed;
    public static void Apply(string theme)
    {
        bool dark = IsDark = theme == "Dark" || theme == "System" && SystemDark;
        var colors = dark
            ? new[] { "#202428", "#191D21", "#2A3035", "#EEF3F4", "#A3AFB7", "#394249", "#41AD98", "#243F39" }
            : new[] { "#F6F7F9", "#EEF0F3", "#FFFFFF", "#20262C", "#6E7782", "#E2E6EA", "#168574", "#DCEEE9" };
        string[] names = ["Page", "Sidebar", "Surface", "Text", "Secondary", "Line", "Accent", "Selection"];
        for (int i = 0; i < names.Length; i++) Application.Current.Resources[names[i]] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(colors[i]));
        Changed?.Invoke();
    }
}
