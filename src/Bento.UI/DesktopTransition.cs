using System.Diagnostics;
using System.Windows.Interop;
using System.Windows.Threading;

namespace Bento.UI;

// Animate DWM copies, then reveal the real windows. Each application is resized only at commit.
internal sealed class DesktopTransition : IDisposable
{
    private readonly List<(TransitionWindow Window, PixelRect From, PixelRect To)> windows = new();
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(16) };
    private readonly Stopwatch clock = new();
    private readonly int duration;
    public DesktopTransition(IEnumerable<(long Id, PixelRect From, PixelRect To)> changes, int duration)
    {
        this.duration = duration;
        try
        {
            foreach (var (id, from, to) in changes.Where(c => c.From != c.To))
            {
                var window = new TransitionWindow(id, from);
                windows.Add((window, from, to)); window.Show(); window.Position(from);
            }
        }
        catch { Dispose(); throw; }
        timer.Tick += (_, _) =>
        {
            double progress = clock.Elapsed.TotalMilliseconds / Math.Max(1, duration);
            try { foreach (var item in windows) item.Window.Position(Motion.Interpolate(item.From, item.To, progress)); }
            catch { Dispose(); return; }
            if (progress >= 1) Dispose();
        };
    }
    public void Play() { clock.Restart(); timer.Start(); }
    public void Dispose()
    {
        timer.Stop();
        foreach (var item in windows) item.Window.Close();
        windows.Clear();
    }
}

internal sealed class TransitionWindow : Window
{
    private WindowThumbnail? thumbnail;
    public TransitionWindow(long source, PixelRect bounds)
    {
        Title = "Bento transition"; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false; ShowActivated = false; Topmost = true; Background = Brushes.Black;
        Left = -32000; Top = -32000; Width = 1; Height = 1;
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            DesktopIntegration.ConfigureOverlay(handle, true);
            thumbnail = new WindowThumbnail(handle, source);
            Position(bounds);
        };
        Closed += (_, _) => thumbnail?.Dispose();
    }
    public void Position(PixelRect bounds)
    {
        DesktopIntegration.PositionOverlay(new WindowInteropHelper(this).Handle, bounds);
        thumbnail?.Update(bounds.Width, bounds.Height);
    }
}
