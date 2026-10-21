using System.Windows.Interop;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

namespace Bento.UI;

// A compositor-driven indicator remains animated while native clients negotiate sizes.
internal sealed class OrganizingWindow : Window
{
    private readonly bool animate;
    public OrganizingWindow(DesktopMonitor monitor, bool animate = true)
    {
        this.animate = animate && SystemParameters.ClientAreaAnimation;
        Title = "Organizing Bento"; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        ShowActivated = false; ShowInTaskbar = false; Topmost = true;
        bool dark = AppTheme.SystemDark;
        Background = SystemParameters.HighContrast ? SystemColors.WindowBrush : new SolidColorBrush(dark ? Color.FromRgb(32, 32, 32) : Color.FromRgb(243, 243, 243));
        Brush text = SystemParameters.HighContrast ? SystemColors.WindowTextBrush : dark ? Brushes.White : Brushes.Black;
        Left = monitor.Bounds.X / monitor.Scale; Top = monitor.Bounds.Y / monitor.Scale;
        Width = monitor.Bounds.Width / monitor.Scale; Height = monitor.Bounds.Height / monitor.Scale;
        var stack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        var rotation = new RotateTransform();
        var spinner = new Ellipse { Width = 26, Height = 26, StrokeThickness = 3, Stroke = text,
            StrokeDashArray = new DoubleCollection { 12, 5 }, RenderTransformOrigin = new Point(.5, .5), RenderTransform = rotation, Margin = new Thickness(0, 0, 0, 16) };
        stack.Children.Add(spinner);
        stack.Children.Add(new TextBlock { Text = "Organizing Bento…", Foreground = text, FontSize = 20 });
        Content = stack;
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            DesktopIntegration.ConfigureOverlay(handle, false);
            if (AppTheme.TransparencyEnabled) WindowAppearance.SetAcrylic(handle, dark);
            DesktopIntegration.PositionOverlay(handle, monitor.Bounds);
        };
        Loaded += (_, _) => { if (this.animate) rotation.BeginAnimation(RotateTransform.AngleProperty,
            new DoubleAnimation(0, 360, TimeSpan.FromSeconds(.9)) { RepeatBehavior = RepeatBehavior.Forever }); };
        Closed += (_, _) => rotation.BeginAnimation(RotateTransform.AngleProperty, null);
    }
    public void Fade(bool visible) => BeginAnimation(OpacityProperty,
        new DoubleAnimation(visible ? 0 : 1, visible ? 1 : 0, TimeSpan.FromMilliseconds(animate ? 220 : 0)));
}
