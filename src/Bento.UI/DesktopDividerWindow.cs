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
    private PixelRect presentedBounds;
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
            Width = horizontal ? 2 : Math.Min(40, Width), Height = horizontal ? Math.Min(40, Height) : 2,
            Background = Brushes.White, Opacity = 0, CornerRadius = new CornerRadius(1),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center
        };
        var area = new Grid { Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0)) };
        area.Children.Add(grip); Content = area;
        MouseEnter += (_, _) => { RefreshContrast(); Animate(OpacityProperty, 1); };
        MouseLeave += (_, _) => { if (!resizing && !IsMouseCaptured && !AreAnyTouchesCaptured) Animate(OpacityProperty, 0); };
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            DesktopIntegration.ConfigureOverlay(handle, false);
            DesktopIntegration.PositionOverlay(handle, divider.Bounds, topmost: false);
        };
    }
    public void RefreshContrast() => grip.Background = WallpaperContrast.At(new(presentedBounds.X + presentedBounds.Width / 2, presentedBounds.Y + presentedBounds.Height / 2), controller.Settings.BackgroundDarkness);
    public void PresentResize(PixelRect bounds)
    {
        bool first = !resizing;
        resizing = true; presentedBounds = bounds;
        bool horizontal = divider.Axis == SplitAxis.Horizontal;
        Animate(WidthProperty, horizontal ? 2 : Math.Min(104, bounds.Width / monitor.Scale));
        Animate(HeightProperty, horizontal ? Math.Min(104, bounds.Height / monitor.Scale) : 2);
        grip.CornerRadius = new CornerRadius(1); Animate(OpacityProperty, 1);
        if (first) RefreshContrast();
        DesktopIntegration.PositionOverlay(new WindowInteropHelper(this).Handle, bounds, topmost: false);
    }
    public void ResetPresentation()
    {
        resizing = false; presentedBounds = divider.Bounds;
        bool horizontal = divider.Axis == SplitAxis.Horizontal;
        Animate(WidthProperty, horizontal ? 2 : Math.Min(40, divider.Bounds.Width / monitor.Scale));
        Animate(HeightProperty, horizontal ? Math.Min(40, divider.Bounds.Height / monitor.Scale) : 2);
        grip.CornerRadius = new CornerRadius(1); Animate(OpacityProperty, IsMouseOver ? 1 : 0);
        DesktopIntegration.PositionOverlay(new WindowInteropHelper(this).Handle, divider.Bounds, topmost: false);
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        finishing = false;
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
