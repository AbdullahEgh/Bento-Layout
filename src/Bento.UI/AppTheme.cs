using Microsoft.Win32;

namespace Bento.UI;

public static class AppTheme
{
    public static bool SystemDark => Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) is int value && value == 0;
    public static bool IsDark { get; private set; }
    public static bool TransparencyEnabled => !SystemParameters.HighContrast &&
        Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "EnableTransparency", 1) is int value && value != 0;
    public static event Action? Changed;
    public static void Apply(string theme)
    {
        bool dark = IsDark = theme == "Dark" || theme == "System" && SystemDark;
        var colors = dark
            ? new[] { "#202428", "#191D21", "#2A3035", "#EEF3F4", "#A3AFB7", "#394249", "#0A84FF", "#183754" }
            : new[] { "#F6F7F9", "#EEF0F3", "#FFFFFF", "#20262C", "#6E7782", "#E2E6EA", "#007AFF", "#DFEDFF" };
        string[] names = ["Page", "Sidebar", "Surface", "Text", "Secondary", "Line", "Accent", "Selection"];
        for (int i = 0; i < names.Length; i++) Application.Current.Resources[names[i]] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(colors[i]));
        void Set(string name, Color color) => Application.Current.Resources[name] = new SolidColorBrush(color);
        Color accent = SystemParameters.WindowGlassColor;
        accent.A = 255;
        Set("Accent", accent);
        Set("AccentText", ForegroundOn(accent));
        Set("ToggleTrack", dark ? Color.FromRgb(72, 72, 72) : Color.FromRgb(232, 232, 232));
        Set("ToggleThumb", dark ? Colors.White : Color.FromRgb(80, 80, 80));
        Set("Selection", dark ? Color.FromRgb(53, 53, 53) : Color.FromRgb(230, 230, 230));
        if (SystemParameters.HighContrast)
        {
            foreach (string name in new[] { "Page", "Sidebar", "Surface", "Selection", "ToggleTrack" }) Set(name, SystemColors.WindowColor);
            foreach (string name in new[] { "Text", "Secondary", "Line", "ToggleThumb" }) Set(name, SystemColors.WindowTextColor);
            Set("Accent", SystemColors.HighlightColor); Set("AccentText", SystemColors.HighlightTextColor);
        }
        Changed?.Invoke();
    }
    public static Color ForegroundOn(Color background)
    {
        static double Linear(byte value) { double c = value / 255d; return c <= .04045 ? c / 12.92 : Math.Pow((c + .055) / 1.055, 2.4); }
        double luminance = .2126 * Linear(background.R) + .7152 * Linear(background.G) + .0722 * Linear(background.B);
        return (luminance + .05) / .05 >= 1.05 / (luminance + .05) ? Colors.Black : Colors.White;
    }
}
