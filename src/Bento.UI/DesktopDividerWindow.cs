using System.Windows.Interop;

namespace Bento.UI;

// Only the gap between real windows receives input; application content remains directly usable.
public sealed class DesktopDividerWindow : Window
{
    private readonly BentoController controller;
    private readonly DesktopMonitor monitor;
    private readonly Divider divider;
    private bool finishing;
    public Guid SplitId => divider.SplitId;
    public PixelRect DesktopBounds => divider.Bounds;

    public DesktopDividerWindow(BentoController controller, DesktopMonitor monitor, Divider divider)
    {
        this.controller = controller; this.monitor = monitor; this.divider = divider;
        Title = "Bento divider";
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true; Background = Brushes.Transparent;
        ShowInTaskbar = false; ShowActivated = false; Topmost = true;
        Left = divider.Bounds.X / monitor.Scale; Top = divider.Bounds.Y / monitor.Scale;
        Width = divider.Bounds.Width / monitor.Scale; Height = divider.Bounds.Height / monitor.Scale;
        bool horizontal = divider.Axis == SplitAxis.Horizontal;
        Cursor = horizontal ? Cursors.SizeWE : Cursors.SizeNS;
        var grip = new Border
        {
            Width = horizontal ? 2 : Math.Min(24, Width), Height = horizontal ? Math.Min(24, Height) : 2,
            Background = Brushes.White, Opacity = .25, CornerRadius = new CornerRadius(1),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center
        };
        var area = new Grid { Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0)) };
        area.Children.Add(grip); Content = area;
        MouseEnter += (_, _) => grip.Opacity = .8;
        MouseLeave += (_, _) => grip.Opacity = .25;
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            DesktopIntegration.ConfigureOverlay(handle, false);
            DesktopIntegration.PositionOverlay(handle, divider.Bounds);
        };
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
    }
}
