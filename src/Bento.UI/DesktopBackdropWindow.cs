using System.Windows.Interop;

namespace Bento.UI;

// A non-interactive dimmer beneath application windows; only gaps and margins remain exposed.
public sealed class DesktopBackdropWindow : Window
{
    private readonly Border shade = new() { Background = Brushes.Black };
    private PixelRect bounds;
    public DesktopBackdropWindow()
    {
        Title = "Bento desktop background";
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true; Background = Brushes.Transparent;
        ShowInTaskbar = false; ShowActivated = false; IsHitTestVisible = false;
        Content = shade;
        SourceInitialized += (_, _) => DesktopIntegration.ConfigureOverlay(new WindowInteropHelper(this).Handle, true);
    }
    public void Present(DesktopMonitor monitor, int darkness, IReadOnlyCollection<long> applications)
    {
        shade.Opacity = Math.Clamp(darkness / 100d, 0, 1);
        if (darkness == 0 || applications.Count == 0) { Hide(); return; }
        bool changed = bounds != monitor.WorkArea;
        bounds = monitor.WorkArea;
        if (!IsVisible)
        {
            Left = bounds.X / monitor.Scale; Top = bounds.Y / monitor.Scale;
            Width = bounds.Width / monitor.Scale; Height = bounds.Height / monitor.Scale;
            Show(); changed = true;
        }
        nint handle = new WindowInteropHelper(this).Handle;
        if (changed) DesktopIntegration.PositionOverlay(handle, bounds, topmost: false);
        DesktopIntegration.PlaceBehindApplications(handle, applications);
    }
}
