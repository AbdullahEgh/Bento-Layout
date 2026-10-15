using Drawing = System.Drawing;

namespace Bento.UI;

public static class WallpaperContrast
{
    private sealed record Sample(string Path, DateTime Modified, int Width, int Height, Drawing.Bitmap Image);
    private static readonly Dictionary<string, Sample> cache = new();
    public static void Invalidate()
    {
        foreach (var item in cache.Values) item.Image.Dispose();
        cache.Clear();
    }
    public static bool UseBlack(byte red, byte green, byte blue, int backgroundDarkness = 0)
    {
        double remaining = 1 - Math.Clamp(backgroundDarkness, 0, 100) / 100d;
        red = (byte)Math.Round(red * remaining); green = (byte)Math.Round(green * remaining); blue = (byte)Math.Round(blue * remaining);
        static double Linear(byte value) { double c = value / 255d; return c <= .04045 ? c / 12.92 : Math.Pow((c + .055) / 1.055, 2.4); }
        return .2126 * Linear(red) + .7152 * Linear(green) + .0722 * Linear(blue) > .179;
    }
    public static Brush At(PixelPoint point, int backgroundDarkness = 0)
    {
        var info = DesktopWallpaper.At(point);
        var color = System.Drawing.SystemColors.Desktop;
        if (info is not null)
        {
            color = Drawing.Color.FromArgb((int)(info.Background & 255), (int)((info.Background >> 8) & 255), (int)((info.Background >> 16) & 255));
            try
            {
                if (File.Exists(info.Path))
                {
                    DateTime modified = File.GetLastWriteTimeUtc(info.Path);
                    if (!cache.TryGetValue(info.Path, out var sample) || sample.Modified != modified)
                    {
                        // Keep only small decoded samples; never retain a full desktop-sized bitmap.
                        if (cache.Count >= 8) Invalidate();
                        sample?.Image.Dispose();
                        using var original = new Drawing.Bitmap(info.Path);
                        sample = new(info.Path, modified, original.Width, original.Height, new Drawing.Bitmap(original, new Drawing.Size(128, 128)));
                        cache[info.Path] = sample;
                    }
                    PixelRect area = info.Position == 5 ? info.Desktop : info.Monitor;
                    double x = point.X - area.X, y = point.Y - area.Y;
                    double sx = area.Width / (double)sample.Width, sy = area.Height / (double)sample.Height;
                    if (info.Position == 1) { x %= sample.Width; y %= sample.Height; }
                    else
                    {
                        if (info.Position == 0) sx = sy = 1;
                        else if (info.Position == 3) sx = sy = Math.Min(sx, sy);
                        else if (info.Position is 4 or 5) sx = sy = Math.Max(sx, sy);
                        x = (x - (area.Width - sample.Width * sx) / 2) / sx;
                        y = (y - (area.Height - sample.Height * sy) / 2) / sy;
                    }
                    if (x >= 0 && y >= 0 && x < sample.Width && y < sample.Height)
                        color = sample.Image.GetPixel(Math.Clamp((int)(x * 128 / sample.Width), 0, 127), Math.Clamp((int)(y * 128 / sample.Height), 0, 127));
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or System.Runtime.InteropServices.ExternalException) { }
        }
        return UseBlack(color.R, color.G, color.B, backgroundDarkness) ? Brushes.Black : Brushes.White;
    }
}
