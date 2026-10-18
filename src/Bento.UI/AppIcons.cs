using System.Windows.Media.Imaging;

namespace Bento.UI;

internal static class AppIcons
{
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool DestroyIcon(nint icon);
    public static System.Drawing.Icon CreateTrayIcon(bool active, bool dark, bool paused = false)
    {
        using var bitmap = new System.Drawing.Bitmap(32, 32);
        using var graphics = System.Drawing.Graphics.FromImage(bitmap);
        graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        int alpha = active ? 255 : 115;
        using var ink = new System.Drawing.SolidBrush(dark ? System.Drawing.Color.FromArgb(alpha, 245, 247, 250) : System.Drawing.Color.FromArgb(alpha, 30, 34, 40));
        using var outline = new System.Drawing.Pen(ink, 2);
        var cells = new[] { new System.Drawing.Rectangle(4, 4, 9, 24), new System.Drawing.Rectangle(17, 4, 11, 10), new System.Drawing.Rectangle(17, 18, 11, 10) };
        foreach (var cell in cells) { if (active && !paused) graphics.FillRectangle(ink, cell); else graphics.DrawRectangle(outline, cell); }
        if (paused) { graphics.FillRectangle(ink, 6, 10, 2, 12); graphics.FillRectangle(ink, 10, 10, 2, 12); }
        nint handle = bitmap.GetHicon();
        try { using var icon = System.Drawing.Icon.FromHandle(handle); return (System.Drawing.Icon)icon.Clone(); }
        finally { DestroyIcon(handle); }
    }
    public static ImageSource Image => BitmapFrame.Create(new Uri("pack://application:,,,/Bento;component/Assets/bento.png"));
    public static System.Drawing.Icon TrayIcon
    {
        get
        {
            using var stream = Application.GetResourceStream(new Uri("pack://application:,,,/Bento;component/Assets/bento.ico")).Stream;
            using var icon = new System.Drawing.Icon(stream, 32, 32);
            return (System.Drawing.Icon)icon.Clone();
        }
    }
}
