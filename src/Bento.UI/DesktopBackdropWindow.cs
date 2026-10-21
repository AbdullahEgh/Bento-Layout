using System.Windows.Interop;
using System.Windows.Media.Animation;

namespace Bento.UI;

// A non-interactive dimmer beneath application windows; only gaps and margins remain exposed.
public sealed class DesktopBackdropWindow : Window
{
    private readonly Border shade = new() { Background = Brushes.Black };
    private PixelRect bounds;
    private double targetOpacity = -1;
    private int animationRevision;
    public DesktopBackdropWindow()
    {
        Title = "Bento desktop background";
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true; Background = Brushes.Transparent;
        ShowInTaskbar = false; ShowActivated = false; IsHitTestVisible = false;
        Content = shade;
        Closed += (_, _) => { animationRevision++; shade.BeginAnimation(OpacityProperty, null); };
        SourceInitialized += (_, _) => DesktopIntegration.ConfigureOverlay(new WindowInteropHelper(this).Handle, true);
    }
    public void Present(DesktopMonitor monitor, int darkness, IReadOnlyCollection<long> applications, bool animate = false, int durationMs = 180)
    {
        if (darkness == 0 || applications.Count == 0) { Dismiss(animate, durationMs); return; }
        bool changed = bounds != monitor.WorkArea;
        bounds = monitor.WorkArea;
        if (!IsVisible)
        {
            shade.BeginAnimation(OpacityProperty, null); shade.Opacity = 0; targetOpacity = -1;
            Left = bounds.X / monitor.Scale; Top = bounds.Y / monitor.Scale;
            Width = bounds.Width / monitor.Scale; Height = bounds.Height / monitor.Scale;
            Show(); changed = true;
        }
        nint handle = new WindowInteropHelper(this).Handle;
        if (changed) DesktopIntegration.PositionOverlay(handle, bounds, topmost: false);
        DesktopIntegration.PlaceBehindApplications(handle, applications);
        FadeTo(Math.Clamp(darkness / 100d, 0, 1), animate, durationMs);
    }

    public void Dismiss(bool animate = false, int durationMs = 180) => FadeTo(0, animate, durationMs);

    private void FadeTo(double target, bool animate, int durationMs)
    {
        // Restacking runs frequently. Never restart an in-flight fade to the same value.
        if (targetOpacity == target && animate) return;
        targetOpacity = target;
        int revision = ++animationRevision;
        double current = shade.Opacity;
        shade.BeginAnimation(OpacityProperty, null);
        shade.Opacity = target;
        if (!animate || !IsVisible || durationMs <= 0 || Math.Abs(current - target) < .001)
        {
            if (target == 0) Hide();
            return;
        }
        var fade = new DoubleAnimation(current, target, TimeSpan.FromMilliseconds(durationMs))
        { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }, FillBehavior = FillBehavior.Stop };
        fade.Completed += (_, _) => { if (revision == animationRevision && target == 0) Hide(); };
        shade.BeginAnimation(OpacityProperty, fade);
    }
}
