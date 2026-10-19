using System.Windows.Interop;
using System.Windows.Threading;

namespace Bento.UI;

// Native desktop acrylic supplies the blur; no text or blueprint covers the target slot.
public sealed class DropPreviewWindow : Window
{
    public PixelRect PreviewBounds { get; private set; }
    public bool AcrylicEnabled { get; private set; }
    public long SlotWindowId { get; internal set; }
    public bool IsDestination { get; private set; } = true;
    private readonly Border surface = new() { BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8) };
    private readonly Border innerEdge = new() { BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(7) };
    private readonly DispatcherTimer motion = new() { Interval = TimeSpan.FromMilliseconds(16) };
    private PixelRect rendered, from;
    private long started;
    private bool conflict;
    private Brush normalEdge = Brushes.Transparent;

    public DropPreviewWindow()
    {
        Title = "Bento drop preview";
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        Background = Brushes.Transparent;
        // Layered + transparent is required for native input to pass through
        // to external application threads. WPF must own the layered style.
        AllowsTransparency = true;
        ShowInTaskbar = false; ShowActivated = false; Topmost = true;
        IsHitTestVisible = false;
        var layers = new Grid(); layers.Children.Add(innerEdge);
        surface.Child = layers; Content = surface;
        motion.Tick += (_, _) =>
        {
            double t = (Environment.TickCount64 - started) / 140d;
            rendered = Motion.Interpolate(from, PreviewBounds, t);
            DesktopIntegration.PositionOverlay(new WindowInteropHelper(this).Handle, rendered);
            if (t >= 1) motion.Stop();
        };
        IsVisibleChanged += (_, _) => { if (!IsVisible) { motion.Stop(); } };
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
        normalEdge = new SolidColorBrush(dark ? Color.FromArgb(IsDestination ? (byte)110 : (byte)50, 255, 255, 255) : Color.FromArgb(IsDestination ? (byte)80 : (byte)28, 0, 0, 0));
        surface.BorderBrush = conflict ? Brushes.Orange : normalEdge;
        innerEdge.BorderBrush = new SolidColorBrush(Color.FromArgb(dark ? (byte)12 : (byte)90, 255, 255, 255));
        surface.Background = AcrylicEnabled
            ? new LinearGradientBrush(dark ? Color.FromArgb(18, 255, 255, 255) : Color.FromArgb(48, 255, 255, 255),
                dark ? Color.FromArgb(8, 0, 0, 0) : Color.FromArgb(16, 255, 255, 255), 90)
            : new SolidColorBrush(dark ? Color.FromRgb(38, 41, 45) : Color.FromRgb(242, 244, 247));
    }
    public void Present(PixelRect bounds, double scale, bool animate = true, bool destination = true, bool conflict = false)
    {
        if (bounds.Width <= 0 || bounds.Height <= 0) { Hide(); return; }
        if (IsDestination != destination) { IsDestination = destination; RefreshAppearance(); }
        this.conflict = conflict;
        surface.BorderBrush = conflict ? Brushes.Orange : normalEdge;
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

// Temporary text-free display dim. Like the slot preview it never activates or
// receives input. The layout owns one dimmer per affected monitor.
internal sealed class PreviewDimWindow : Window
{
    private PixelRect? presented;
    public PreviewDimWindow()
    {
        Title = "Bento preview dim"; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true; Background = new SolidColorBrush(Color.FromArgb(115, 0, 0, 0));
        ShowInTaskbar = false; ShowActivated = false; Topmost = true; IsHitTestVisible = false;
        SourceInitialized += (_, _) => DesktopIntegration.ConfigureOverlay(new WindowInteropHelper(this).Handle, true);
    }
    public void PlaceBelow(nint preview)
    {
        if (IsVisible && preview != 0) DesktopIntegration.PlaceBelow(new WindowInteropHelper(this).Handle, preview);
    }
    public bool Present(PixelRect bounds, double scale)
    {
        if (IsVisible && presented == bounds) return false;
        presented = bounds;
        if (!IsVisible)
        {
            Left = bounds.X / scale; Top = bounds.Y / scale; Width = bounds.Width / scale; Height = bounds.Height / scale;
            Show();
        }
        DesktopIntegration.PositionOverlay(new WindowInteropHelper(this).Handle, bounds);
        return true;
    }
}
