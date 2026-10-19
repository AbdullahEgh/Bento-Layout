using System.Windows.Interop;

namespace Bento.UI;

internal sealed class PausedWindowShade : Window
{
    private PixelRect? bounds;
    public PausedWindowShade()
    {
        Title = "Bento paused window"; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true; Background = Brushes.Transparent;
        Content = new Border { Background = new SolidColorBrush(Color.FromArgb(77, 0, 0, 0)), CornerRadius = new CornerRadius(8) };
        ShowInTaskbar = false; ShowActivated = false; IsHitTestVisible = false;
        SourceInitialized += (_, _) => DesktopIntegration.ConfigureOverlay(new WindowInteropHelper(this).Handle, true);
    }
    public void Present(long application, PixelRect rect, double scale)
    {
        bool moved = bounds != rect; bounds = rect;
        if (!IsVisible)
        {
            Left = rect.X / scale; Top = rect.Y / scale; Width = rect.Width / scale; Height = rect.Height / scale;
            Show(); moved = true;
        }
        var handle = new WindowInteropHelper(this).Handle;
        if (moved) DesktopIntegration.PositionOverlay(handle, rect, topmost: false);
        DesktopIntegration.PlaceAboveApplication(handle, application);
    }
}
