using System.Windows.Interop;
using System.Windows.Threading;

namespace Bento.UI;

// Native desktop acrylic supplies the blur; no text or blueprint covers the target slot.
public sealed class DropPreviewWindow : Window
{
    public PixelRect PreviewBounds { get; private set; }
    public bool AcrylicEnabled { get; private set; }
    private readonly Border surface = new() { BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12) };
    private readonly DispatcherTimer motion = new() { Interval = TimeSpan.FromMilliseconds(16) };
    private PixelRect rendered, from;
    private long started;

    public DropPreviewWindow()
    {
        Title = "Bento drop preview";
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        Background = Brushes.Transparent;
        ShowInTaskbar = false; ShowActivated = false; Topmost = true;
        IsHitTestVisible = false; Content = surface;
        motion.Tick += (_, _) =>
        {
            double t = (Environment.TickCount64 - started) / 140d;
            rendered = Motion.Interpolate(from, PreviewBounds, t);
            DesktopIntegration.PositionOverlay(new WindowInteropHelper(this).Handle, rendered);
            if (t >= 1) motion.Stop();
        };
        IsVisibleChanged += (_, _) => { if (!IsVisible) motion.Stop(); };
        AppTheme.Changed += RefreshAppearance;
        Closed += (_, _) => { motion.Stop(); AppTheme.Changed -= RefreshAppearance; };
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            DesktopIntegration.ConfigureOverlay(handle, true);
            if (HwndSource.FromHwnd(handle)?.CompositionTarget is { } target) target.BackgroundColor = Colors.Transparent;
            RefreshAppearance();
            DesktopIntegration.PositionOverlay(handle, PreviewBounds);
        };
    }
    private void RefreshAppearance()
    {
        bool dark = AppTheme.SystemDark;
        var handle = new WindowInteropHelper(this).Handle;
        AcrylicEnabled = handle != 0 && !SystemParameters.HighContrast && WindowAppearance.SetAcrylic(handle, dark);
        surface.BorderBrush = new SolidColorBrush(dark ? Color.FromArgb(90, 255, 255, 255) : Color.FromArgb(65, 0, 0, 0));
        surface.Background = AcrylicEnabled ? Brushes.Transparent : new SolidColorBrush(dark ? Color.FromRgb(45, 49, 53) : Color.FromRgb(238, 241, 245));
    }
    public void Present(PixelRect bounds, double scale, bool animate = true)
    {
        if (bounds.Width <= 0 || bounds.Height <= 0) { Hide(); return; }
        if (IsVisible && PreviewBounds == bounds) return;
        PreviewBounds = bounds;
        if (!IsVisible)
        {
            Left = bounds.X / scale; Top = bounds.Y / scale;
            Width = bounds.Width / scale; Height = bounds.Height / scale;
            rendered = bounds; Show();
        }
        if (animate && rendered != bounds) { from = rendered; started = Environment.TickCount64; motion.Start(); }
        else { motion.Stop(); rendered = bounds; DesktopIntegration.PositionOverlay(new WindowInteropHelper(this).Handle, bounds); }
    }
}
