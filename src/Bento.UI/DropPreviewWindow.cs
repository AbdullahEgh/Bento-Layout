using System.Windows.Interop;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace Bento.UI;

// A single, temporary, click-through destination rectangle. Never covers the workspace at rest.
public sealed class DropPreviewWindow : Window
{
    public PixelRect PreviewBounds { get; private set; }
    private readonly TextBlock hint = new() { Foreground = Brushes.White, FontSize = 12, FontWeight = FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center };
    private readonly ProgressBar progress = new() { Minimum = 0, Maximum = 1, Height = 3, Width = 112, Margin = new Thickness(0, 8, 0, 0) };
    private readonly DispatcherTimer motion = new() { Interval = TimeSpan.FromMilliseconds(16) };
    private PixelRect rendered, from;
    private long started;

    public DropPreviewWindow()
    {
        Title = "Bento drop preview";
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true; Background = Brushes.Transparent;
        ShowInTaskbar = false; ShowActivated = false; Topmost = true;
        IsHitTestVisible = false;
        var surface = new Grid();
        surface.Children.Add(new Border
        {
            BorderBrush = new SolidColorBrush(Color.FromRgb(95, 209, 184)),
            BorderThickness = new Thickness(2), CornerRadius = new CornerRadius(12),
            Background = new SolidColorBrush(Color.FromArgb(28, 42, 171, 145))
        });
        var label = new StackPanel(); label.Children.Add(hint); label.Children.Add(progress);
        surface.Children.Add(new Border { Child = label, Padding = new Thickness(16, 10, 16, 10), CornerRadius = new CornerRadius(14),
            Background = new SolidColorBrush(Color.FromArgb(235, 29, 43, 43)), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        Content = surface;
        motion.Tick += (_, _) =>
        {
            double t = (Environment.TickCount64 - started) / 140d;
            rendered = Motion.Interpolate(from, PreviewBounds, t);
            DesktopIntegration.PositionOverlay(new WindowInteropHelper(this).Handle, rendered);
            if (t >= 1) motion.Stop();
        };
        IsVisibleChanged += (_, _) => { if (!IsVisible) motion.Stop(); };
        Closed += (_, _) => motion.Stop();
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            DesktopIntegration.ConfigureOverlay(handle, true);
            DesktopIntegration.PositionOverlay(handle, PreviewBounds);
        };
    }

    public void Present(PixelRect bounds, double scale, string text = "Release to swap", double holdProgress = 0, bool animate = true)
    {
        if (bounds.Width <= 0 || bounds.Height <= 0) { Hide(); return; }
        hint.Text = text; progress.Value = holdProgress;
        progress.Visibility = text is "Hold to split" or "Release to split" ? Visibility.Visible : Visibility.Collapsed;
        if (IsVisible && PreviewBounds == bounds) return;
        PreviewBounds = bounds;
        if (!IsVisible)
        {
            Left = bounds.X / scale; Top = bounds.Y / scale;
            Width = bounds.Width / scale; Height = bounds.Height / scale;
            rendered = bounds;
            Show();
            if (animate) BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(100)));
        }
        if (animate && rendered != bounds) { from = rendered; started = Environment.TickCount64; motion.Start(); }
        else { motion.Stop(); rendered = bounds; DesktopIntegration.PositionOverlay(new WindowInteropHelper(this).Handle, bounds); }
    }
}
