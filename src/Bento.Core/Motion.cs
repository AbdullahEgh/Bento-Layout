namespace Bento.Core;

public static class Motion
{
    public static double Ease(double progress)
    {
        double t = Math.Clamp(progress, 0, 1);
        return t * t * t * (t * (6 * t - 15) + 10);
    }
    public static PixelRect Interpolate(PixelRect from, PixelRect to, double progress)
    {
        double t = Ease(progress);
        int Mix(int a, int b) => (int)Math.Round(a + (b - (double)a) * t);
        int left = Mix(from.X, to.X), top = Mix(from.Y, to.Y);
        return new(left, top, Math.Max(1, Mix(from.Right, to.Right) - left), Math.Max(1, Mix(from.Bottom, to.Bottom) - top));
    }
}
