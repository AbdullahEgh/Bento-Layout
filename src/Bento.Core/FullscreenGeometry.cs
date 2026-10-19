namespace Bento.Core;

public static class FullscreenGeometry
{
    // Maximization and a borderless fullscreen presentation are distinct. This
    // deliberately declines captioned/custom presentation modes it cannot prove.
    public static bool Reserve(PixelRect window, PixelRect screen, bool maximized, bool caption, PixelRect? applied, bool? appliedCaption)
    {
        if (maximized) return false;
        // A full-screen-sized allocation written by Bento is not evidence of a
        // presentation transition. A later frame/style change is observable.
        if (applied is { } slot && appliedCaption == caption && NativeFrameFit.Accepts(window, slot)) return false;
        return Borderless(window, screen, false, false);
    }
    public static bool Borderless(PixelRect window, PixelRect screen, bool maximized, bool caption) => !maximized && !caption &&
        Math.Abs(window.X - screen.X) <= 2 && Math.Abs(window.Y - screen.Y) <= 2 &&
        Math.Abs(window.Right - screen.Right) <= 2 && Math.Abs(window.Bottom - screen.Bottom) <= 2;
}
