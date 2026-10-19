using System.Diagnostics;
using System.Windows.Interop;

namespace Bento.UI;

internal sealed class WaitingWindow : Window
{
    private readonly BentoController controller;
    private bool dragging;
    private readonly StackPanel items = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    public WaitingWindow(BentoController controller, DesktopMonitor monitor, IReadOnlyList<AppWindow> windows)
    {
        this.controller = controller;
        Title = "Bento waiting windows"; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true; Background = new SolidColorBrush(Color.FromArgb(100, 0, 0, 0));
        ShowInTaskbar = false; ShowActivated = false; Topmost = true;
        Left = monitor.Bounds.X / monitor.Scale; Top = monitor.Bounds.Y / monitor.Scale;
        Width = monitor.Bounds.Width / monitor.Scale; Height = monitor.Bounds.Height / monitor.Scale;
        Content = items;
        foreach (var window in windows)
        {
            ImageSource image = AppIcons.Image;
            try
            {
                using var process = Process.GetProcessById((int)window.ProcessId);
                using var icon = System.Drawing.Icon.ExtractAssociatedIcon(process.MainModule!.FileName!);
                if (icon is not null) image = Imaging.CreateBitmapSourceFromHIcon(icon.Handle, Int32Rect.Empty, System.Windows.Media.Imaging.BitmapSizeOptions.FromWidthAndHeight(64, 64));
            }
            catch { /* A protected app still has a draggable fallback icon. */ }
            var card = new Border { Width = 112, Height = 112, Margin = new Thickness(8), CornerRadius = new CornerRadius(20),
                Background = new SolidColorBrush(Color.FromArgb(220, 45, 48, 54)), Cursor = Cursors.Hand,
                Child = new Image { Source = image, Width = 80, Height = 80 } };
            System.Windows.Automation.AutomationProperties.SetName(card, window.Title);
            card.MouseLeftButtonDown += (_, e) =>
            {
                if (!controller.BeginWaitingDrag(window.Id)) return;
                dragging = true; Background = Brushes.Transparent; items.Visibility = Visibility.Hidden;
                CaptureMouse(); e.Handled = true;
            };
            items.Children.Add(card);
        }
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            DesktopIntegration.ConfigureOverlay(handle, false);
            DesktopIntegration.PositionOverlay(handle, monitor.Bounds);
        };
        MouseMove += (_, _) => { if (dragging) controller.PreviewDrag(WindowCatalog.Cursor); };
        MouseLeftButtonUp += (_, e) =>
        {
            if (!dragging) { controller.DismissWaiting(); return; }
            dragging = false; ReleaseMouseCapture(); controller.FinishDrag(WindowCatalog.Cursor);
            controller.EndWaitingDrag(); e.Handled = true;
        };
        LostMouseCapture += (_, _) => { if (dragging) { dragging = false; controller.CancelDrag(); controller.EndWaitingDrag(); } };
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { controller.CancelDrag(); controller.DismissWaiting(); e.Handled = true; } };
    }
}
