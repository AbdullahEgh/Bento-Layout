using System.Windows.Interop;
using System.Windows.Media.Animation;

namespace Bento.UI;

// Only the gap between real windows receives input; application content remains directly usable.
public sealed class DesktopDividerWindow : Window
{
    private readonly BentoController controller;
    private readonly DesktopMonitor monitor;
    private Divider divider;
    private bool finishing;
    private readonly Border grip;
    private bool resizing;
    private bool cueSuppressesInk;
    private PixelRect presentedBounds;
    private ResizeHandle? geometry;
    private IReadOnlyList<ResizeHandle>? geometryGroup;
    private readonly List<Border> segments = new();
    public Guid SplitId => divider.SplitId;
    public PixelRect DesktopBounds => divider.Bounds;
    public string MonitorId => monitor.Id;
    public double MonitorScale => monitor.Scale;
    private void Animate(DependencyProperty property, double value)
    {
        if ((double)grip.GetAnimationBaseValue(property) == value) return;
        double from = (double)grip.GetValue(property);
        grip.BeginAnimation(property, null); grip.SetValue(property, value);
        if (controller.Settings.Animate && SystemParameters.ClientAreaAnimation)
            grip.BeginAnimation(property, new DoubleAnimation(from, value, TimeSpan.FromMilliseconds(120))
            { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }, FillBehavior = FillBehavior.Stop });
    }
    public void UpdateDivider(Divider value)
    {
        if (divider == value) return;
        divider = value; ResetPresentation();
    }

    public DesktopDividerWindow(BentoController controller, DesktopMonitor monitor, Divider divider)
    {
        this.controller = controller; this.monitor = monitor; this.divider = divider;
        presentedBounds = divider.Bounds;
        Title = "Bento divider";
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true; Background = Brushes.Transparent;
        ShowInTaskbar = false; ShowActivated = false; Topmost = false;
        Left = divider.Bounds.X / monitor.Scale; Top = divider.Bounds.Y / monitor.Scale;
        Width = divider.Bounds.Width / monitor.Scale; Height = divider.Bounds.Height / monitor.Scale;
        bool horizontal = divider.Axis == SplitAxis.Horizontal;
        Cursor = horizontal ? Cursors.SizeWE : Cursors.SizeNS;
        grip = new Border
        {
            Width = horizontal ? 2 : Math.Min(80, Width), Height = horizontal ? Math.Min(80, Height) : 2,
            Background = Brushes.White, Opacity = 0, CornerRadius = new CornerRadius(1),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center
        };
        var area = new Grid { Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0)) };
        area.Children.Add(grip); Content = area;
        MouseEnter += (_, _) => { RefreshContrast(); if (!cueSuppressesInk) Animate(OpacityProperty, 1); };
        MouseLeave += (_, _) => { if (!resizing && !IsMouseCaptured && !AreAnyTouchesCaptured) Animate(OpacityProperty, 0); };
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            DesktopIntegration.ConfigureOverlay(handle, false);
            DesktopIntegration.PositionOverlay(handle, divider.Bounds, topmost: false);
        };
    }
    public void SuppressInkForJoin(bool suppress)
    {
        if (cueSuppressesInk == suppress) return;
        cueSuppressesInk = suppress;
        Animate(OpacityProperty, !suppress && IsMouseOver ? 1 : 0);
    }
    public void UpdateHandle(ResizeHandle value, IReadOnlyList<ResizeHandle> all)
    {
        if (ReferenceEquals(geometry, value) && ReferenceEquals(geometryGroup, all)) return;
        geometry = value; geometryGroup = all;
        ResetPresentation();
    }
    public void RefreshContrast()
    {
        var ink = WallpaperContrast.At(new(presentedBounds.X + presentedBounds.Width / 2, presentedBounds.Y + presentedBounds.Height / 2), controller.Settings.BackgroundDarkness);
        if (segments.Count == 0) grip.Background = ink;
        else foreach (var segment in segments) segment.Background = ink;
    }
    private void RenderInk(PixelRect bounds, bool shared)
    {
        segments.Clear(); grip.Child = null;
        bool h = divider.Axis == SplitAxis.Horizontal;
        double span = (h ? bounds.Height : bounds.Width) / monitor.Scale;
        Animate(WidthProperty, h ? 2 : shared ? span : Math.Min(80, span));
        Animate(HeightProperty, h ? shared ? span : Math.Min(80, span) : 2);
        if (shared && geometry is not null && geometryGroup is not null)
        {
            grip.Background = Brushes.Transparent;
            var canvas = new Canvas(); grip.Child = canvas;
            var centers = geometryGroup.Where(local => ResizeHandles.Contains(geometry, local)).Select(local =>
                h ? (local.Divider.Bounds.Y + local.Divider.Bounds.Height / 2d - bounds.Y) / monitor.Scale
                    : (local.Divider.Bounds.X + local.Divider.Bounds.Width / 2d - bounds.X) / monitor.Scale).Distinct();
            foreach (var piece in GripInk.Segments(span, centers))
            {
                var segment = new Border { Width = h ? 2 : piece.End - piece.Start, Height = h ? piece.End - piece.Start : 2,
                    Opacity = piece.Local ? 1 : .45, CornerRadius = new CornerRadius(1), IsHitTestVisible = false };
                if (h) Canvas.SetTop(segment, piece.Start); else Canvas.SetLeft(segment, piece.Start);
                segments.Add(segment); canvas.Children.Add(segment);
            }
        }
        RefreshContrast();
    }
    public void PresentResize(PixelRect bounds)
    {
        bool first = !resizing, moved = presentedBounds != bounds;
        resizing = true; presentedBounds = bounds;
        // A local gesture temporarily uses its own section, while a held shared
        // seam retains the segmented long line and opaque local pills.
        if (first || moved) RenderInk(bounds, geometry?.Shared == true &&
            (divider.Axis == SplitAxis.Horizontal ? bounds.Height == divider.Bounds.Height : bounds.Width == divider.Bounds.Width));
        Animate(OpacityProperty, 1);
        if (moved) DesktopIntegration.MoveOverlay(new WindowInteropHelper(this).Handle, bounds);
    }
    public void ResetPresentation()
    {
        bool moved = presentedBounds != divider.Bounds;
        resizing = false; presentedBounds = divider.Bounds;
        RenderInk(divider.Bounds, geometry?.Shared == true);
        Animate(OpacityProperty, !cueSuppressesInk && IsMouseOver ? 1 : 0);
        if (moved) DesktopIntegration.MoveOverlay(new WindowInteropHelper(this).Handle, divider.Bounds);
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        finishing = false; RefreshContrast(); Animate(OpacityProperty, 1);
        controller.BeginDivider(monitor, divider); CaptureMouse(); e.Handled = true;
    }
    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        finishing = true;
        ReleaseMouseCapture();
        controller.FinishDrag();
        e.Handled = true;
    }
    protected override void OnLostMouseCapture(MouseEventArgs e)
    {
        base.OnLostMouseCapture(e);
        if (!finishing && controller.Dragging) controller.CancelDrag();
        if (!IsMouseOver) Animate(OpacityProperty, 0);
    }
    private PixelPoint TouchPosition(TouchEventArgs e)
    {
        var point = PointToScreen(e.GetTouchPoint(this).Position);
        return new((int)Math.Round(point.X), (int)Math.Round(point.Y));
    }
    protected override void OnTouchDown(TouchEventArgs e)
    {
        base.OnTouchDown(e);
        e.Handled = true;
        if (AreAnyTouchesCaptured) return;
        finishing = false; RefreshContrast(); Animate(OpacityProperty, 1);
        controller.BeginDivider(monitor, divider, TouchPosition(e)); CaptureTouch(e.TouchDevice);
    }
    protected override void OnTouchMove(TouchEventArgs e)
    {
        base.OnTouchMove(e); e.Handled = true;
        if (e.TouchDevice.Captured == this) controller.PreviewDrag(TouchPosition(e));
    }
    protected override void OnTouchUp(TouchEventArgs e)
    {
        base.OnTouchUp(e); e.Handled = true;
        if (e.TouchDevice.Captured != this) return;
        var point = TouchPosition(e); finishing = true;
        ReleaseTouchCapture(e.TouchDevice); controller.FinishDrag(point);
    }
    protected override void OnLostTouchCapture(TouchEventArgs e)
    {
        base.OnLostTouchCapture(e);
        if (!finishing && controller.Dragging) controller.CancelDrag();
        if (!IsMouseOver) Animate(OpacityProperty, 0);
    }
}
