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
    private readonly DropCue cue = new();
    private PixelRect rendered, from;
    private long started;

    public DropPreviewWindow()
    {
        Title = "Bento drop preview";
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        Background = Brushes.Transparent;
        ShowInTaskbar = false; ShowActivated = false; Topmost = true;
        IsHitTestVisible = false;
        var layers = new Grid(); layers.Children.Add(innerEdge); layers.Children.Add(cue);
        surface.Child = layers; Content = surface;
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
    public void Present(PixelRect bounds, double scale, bool animate = true, Placement placement = Placement.Center, double progress = 0, bool conflict = false)
    {
        if (bounds.Width <= 0 || bounds.Height <= 0) { Hide(); return; }
        cue.Placement = placement; cue.Progress = progress; cue.Conflict = conflict; cue.InvalidateVisual();
        surface.BorderBrush = new SolidColorBrush(conflict ? Colors.Orange : Color.FromRgb(61, 199, 186));
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

// Shape-only cues remain legible without covering the window with instructions.
internal sealed class DropCue : FrameworkElement
{
    public Placement Placement { get; set; }
    public double Progress { get; set; }
    public bool Conflict { get; set; }
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        double x = ActualWidth / 2, y = ActualHeight / 2;
        var ink = new SolidColorBrush(Conflict ? Colors.Orange : Color.FromRgb(61, 199, 186));
        var pen = new Pen(ink, 2) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(235, 24, 27, 30)), null, new Rect(x - 25, y - 25, 50, 50), 15, 15);
        void Line(double ax, double ay, double bx, double by) => dc.DrawLine(pen, new Point(x + ax, y + ay), new Point(x + bx, y + by));
        if (Conflict)
        {
            Line(0, -12, -12, 10); Line(-12, 10, 12, 10); Line(12, 10, 0, -12);
            Line(0, -4, 0, 2); dc.DrawEllipse(ink, null, new Point(x, y + 6), 1.2, 1.2);
        }
        else if (Placement == Placement.Center && Progress <= 0)
        {
            Line(-11, -5, 11, -5); Line(6, -10, 11, -5); Line(6, 0, 11, -5);
            Line(11, 5, -11, 5); Line(-6, 0, -11, 5); Line(-6, 10, -11, 5);
        }
        else
        {
            dc.DrawRoundedRectangle(null, pen, new Rect(x - 12, y - 10, 24, 20), 3, 3);
            if (Placement is Placement.Top or Placement.Bottom) Line(-12, 0, 12, 0);
            else Line(0, -10, 0, 10);
        }
        if (Progress > 0 && Progress < 1 && !Conflict)
        {
            double angle = Progress * Math.PI * 2 - Math.PI / 2;
            var path = new StreamGeometry();
            using (var geometry = path.Open())
            {
                geometry.BeginFigure(new Point(x, y - 30), false, false);
                geometry.ArcTo(new Point(x + Math.Cos(angle) * 30, y + Math.Sin(angle) * 30), new Size(30, 30), 0, Progress > .5, SweepDirection.Clockwise, true, false);
            }
            dc.DrawGeometry(null, pen, path);
        }
    }
}
