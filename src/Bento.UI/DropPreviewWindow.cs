using System.Windows.Interop;
using System.Windows.Threading;

namespace Bento.UI;

// Native desktop acrylic supplies the blur; no text or blueprint covers the target slot.
public sealed class DropPreviewWindow : Window
{
    public PixelRect PreviewBounds { get; private set; }
    public bool AcrylicEnabled { get; private set; }
    private readonly Border surface = new() { BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8) };
    private readonly Border innerEdge = new() { BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(7) };
    private readonly DispatcherTimer motion = new() { Interval = TimeSpan.FromMilliseconds(16) };
    private PixelRect rendered, from;
    private long started;

    public DropPreviewWindow()
    {
        Title = "Bento drop preview";
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        Background = Brushes.Transparent;
        ShowInTaskbar = false; ShowActivated = false; Topmost = true;
        IsHitTestVisible = false; surface.Child = innerEdge; Content = surface;
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
        // Match the native eight-DIP corner, with a quiet rim and a soft glass highlight.
        // Tint the acrylic lightly so the destination remains recognizable underneath.
        surface.BorderBrush = new SolidColorBrush(dark ? Color.FromArgb(65, 255, 255, 255) : Color.FromArgb(38, 0, 0, 0));
        innerEdge.BorderBrush = new SolidColorBrush(Color.FromArgb(dark ? (byte)12 : (byte)90, 255, 255, 255));
        surface.Background = AcrylicEnabled
            ? new LinearGradientBrush(dark ? Color.FromArgb(18, 255, 255, 255) : Color.FromArgb(48, 255, 255, 255),
                dark ? Color.FromArgb(8, 0, 0, 0) : Color.FromArgb(16, 255, 255, 255), 90)
            : new SolidColorBrush(dark ? Color.FromRgb(38, 41, 45) : Color.FromRgb(242, 244, 247));
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
