using System.Windows.Interop;
using System.Windows.Threading;

namespace Bento.UI;

internal sealed class JoinedSeamCue : Window
{
    private readonly DispatcherTimer fade = new() { Interval = TimeSpan.FromMilliseconds(16) };
    private readonly long started = Environment.TickCount64;
    public PixelRect Bounds { get; }
    public JoinedSeamCue(ResizeHandle joined, IReadOnlyList<ResizeHandle> handles, DesktopMonitor monitor, int darkness)
    {
        Bounds = joined.Divider.Bounds;
        Title = "Bento joined seam"; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true; Background = Brushes.Transparent; ShowInTaskbar = false; ShowActivated = false; IsHitTestVisible = false;
        Left = Bounds.X / monitor.Scale; Top = Bounds.Y / monitor.Scale; Width = Bounds.Width / monitor.Scale; Height = Bounds.Height / monitor.Scale;
        bool h = joined.Divider.Axis == SplitAxis.Horizontal;
        var ink = WallpaperContrast.At(new(Bounds.X + Bounds.Width / 2, Bounds.Y + Bounds.Height / 2), darkness);
        var canvas = new Canvas(); Content = canvas;
        var centers = handles.Where(local => ResizeHandles.Contains(joined, local)).Select(local => h
            ? (local.Divider.Bounds.Y + local.Divider.Bounds.Height / 2d - Bounds.Y) / monitor.Scale
            : (local.Divider.Bounds.X + local.Divider.Bounds.Width / 2d - Bounds.X) / monitor.Scale).Distinct();
        foreach (var piece in GripInk.Segments(h ? Height : Width, centers))
        {
            var segment = new Border { Width = h ? 2 : piece.End - piece.Start, Height = h ? piece.End - piece.Start : 2,
                Background = ink, Opacity = piece.Local ? 1 : .45, CornerRadius = new CornerRadius(1) };
            Canvas.SetLeft(segment, h ? (Width - 2) / 2 : piece.Start); Canvas.SetTop(segment, h ? piece.Start : (Height - 2) / 2);
            canvas.Children.Add(segment);
        }
        SourceInitialized += (_, _) => { var handle = new WindowInteropHelper(this).Handle; DesktopIntegration.ConfigureOverlay(handle, true); DesktopIntegration.PositionOverlay(handle, Bounds, topmost: false); };
        fade.Tick += (_, _) =>
        {
            double elapsed = (Environment.TickCount64 - started) / 1000d;
            Opacity = ResizeHandles.JoinOpacity(elapsed);
            if (elapsed >= .55) Close();
        };
        Closed += (_, _) => fade.Stop(); fade.Start();
    }
}
