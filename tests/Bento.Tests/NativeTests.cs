using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using System.Text.Json;
using Bento.Core;
using Bento.UI;
using Bento.Windows;
using static Bento.Tests.Program;

namespace Bento.Tests;

internal static class NativeTests
{
    internal static int Fixture(string title)
    {
        var app = new Application();
        app.Run(new Window { Title = title, Width = 640, Height = 480, MinWidth = 180, MinHeight = 120,
            Content = new TextBlock { Text = title, FontSize = 28, Margin = new Thickness(30) } });
        return 0;
    }
    internal static void RunAll(bool interactive = false, int fixtureCount = 3)
    {
        if (fixtureCount is < 3 or > 12 || (!interactive && fixtureCount != 3))
            throw new ArgumentOutOfRangeException(nameof(fixtureCount));
        if (Application.Current is null)
        {
            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            app.Resources.MergedDictionaries.Add(new ResourceDictionary { Source = new Uri("pack://application:,,,/Bento;component/Theme.xaml") });
        }
        bool isolated = true;
        Run("Native tests are isolated from a running Bento app", () =>
        {
            var running = Process.GetProcessesByName("Bento");
            try
            {
                if (running.Length > 0)
                {
                    isolated = false;
                    throw new Exception("Exit the running Bento tray app before native tests; two managers would compete over fixture windows.");
                }
            }
            finally { foreach (var process in running) process.Dispose(); }
        });
        if (!isolated) return;
        Run("Global shortcut registers and releases", () =>
        {
            bool registered = DesktopIntegration.RegisterShortcut(0, 0x5B20, 7, 0x78);
            int error = DesktopIntegration.ShortcutError;
            try { if (!registered) throw new Exception($"RegisterHotKey returned Windows error {error}."); }
            finally { if (registered) DesktopIntegration.UnregisterShortcut(0, 0x5B20); }
        });
        string prefix = $"Bento fixture {Guid.NewGuid():N}";
        var processes = new List<Process>();
        try
        {
            for (int i = 1; i <= fixtureCount; i++)
            {
                var info = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true };
                info.ArgumentList.Add("--fixture"); info.ArgumentList.Add($"{prefix} {i}");
                processes.Add(Process.Start(info)!);
            }
            AppWindow[] fixtures = [];
            var wait = Stopwatch.StartNew();
            while (wait.Elapsed < TimeSpan.FromSeconds(15))
            {
                fixtures = WindowCatalog.Discover().Where(w => w.Title.StartsWith(prefix, StringComparison.Ordinal)).OrderBy(w => w.Title).ToArray();
                if (fixtures.Length == fixtureCount) break;
                Pump(); Thread.Sleep(100);
            }
            Equal(fixtureCount, fixtures.Length);
            Run($"Native discovery finds {fixtureCount} external processes", () =>
            { Equal(fixtureCount, fixtures.Select(w => w.ProcessId).Distinct().Count()); Check(fixtures.All(w => w.ProcessId != Environment.ProcessId)); });
            var native = new WindowController();
            var originals = fixtures.Select(w => native.Capture(w.Id)).ToArray();
            long gestureTime = 0;
            using var controller = new BentoController(() => WindowCatalog.Discover(includeMinimized: false)
                .Where(w => w.Title.StartsWith(prefix, StringComparison.Ordinal)).OrderBy(w => w.Title).ToArray(),
                new BentoSettings(Animate: true), interactive ? null : () => gestureTime);
            var monitor = WindowCatalog.Monitors().First();
            long foreground = WindowCatalog.Foreground;
            controller.ArrangeDesktop(); Pump();
            if (interactive)
            {
                Run($"All {fixtureCount} test windows occupy their desktop regions", () =>
                {
                    Equal(fixtureCount, WindowCatalog.Monitors().Sum(m => controller.Layout(m).Regions.Count));
                    foreach (var display in WindowCatalog.Monitors()) VerifyBounds(controller.Layout(display), native);
                });
                if (!Environment.GetCommandLineArgs().Contains("--hide-ui")) controller.ShowInterface();
                Directory.CreateDirectory(".tools");
                string statePath = Path.Combine(Directory.GetCurrentDirectory(), ".tools", "interactive-state.json");
                var nativeEvents = new List<object>();
                using var interactionObserver = new DesktopEvents();
                interactionObserver.NativeDrag += (id, starting) =>
                {
                    if (!controller.Windows.Any(w => w.Id == id) || !WindowCatalog.Exists(id)) return;
                    var point = WindowCatalog.Cursor;
                    nativeEvents.Add(new { Time = DateTimeOffset.UtcNow, Id = id, Starting = starting, Cursor = point,
                        Bounds = native.VisibleBounds(id), ResizeHit = native.IsResizeInteraction(id, point) });
                    if (nativeEvents.Count > 40) nativeEvents.RemoveAt(0);
                };
                var observations = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
                observations.Tick += (_, _) =>
                {
                    var state = new
                    {
                        Time = DateTimeOffset.UtcNow, controller.Dragging, controller.Status,
                        Cursor = WindowCatalog.Cursor,
                        NativeEvents = nativeEvents.ToArray(),
                        Monitors = WindowCatalog.Monitors(),
                        Regions = WindowCatalog.Monitors().SelectMany(m => controller.Layout(m).Regions),
                        Windows = controller.Windows.Where(w => WindowCatalog.Exists(w.Id)).Select(w => new { w.Id, w.Title, Bounds = native.VisibleBounds(w.Id) }),
                        Previews = Application.Current!.Windows.OfType<DropPreviewWindow>().Where(w => w.IsVisible).Select(w => w.PreviewBounds)
                    };
                    File.WriteAllText(statePath + ".tmp", JsonSerializer.Serialize(state));
                    File.Move(statePath + ".tmp", statePath, true);
                };
                observations.Start();
                var timeout = new DispatcherTimer { Interval = TimeSpan.FromMinutes(10) };
                timeout.Tick += (_, _) => { timeout.Stop(); Application.Current!.Shutdown(); };
                timeout.Start(); Application.Current!.Run(); return;
            }
            Run("Desktop arrangement keeps the active application focused", () => Equal(foreground, WindowCatalog.Foreground));
            Run("Desktop arrangement has no blueprint or visible drop preview", () =>
            {
                Check(!Application.Current!.Windows.OfType<DropPreviewWindow>().Any(w => w.IsVisible));
                Check(!Application.Current.Windows.Cast<Window>().Any(w => w.Title == "Bento" && w.IsVisible));
            });
            Run("Only divider gaps receive desktop helper windows", () =>
            {
                var handles = Application.Current!.Windows.OfType<DesktopDividerWindow>().ToArray();
                Equal(controller.Layout(monitor).Dividers.Count, handles.Length);
                foreach (var handle in handles)
                    foreach (var region in controller.Layout(monitor).Regions)
                    {
                        var a = handle.DesktopBounds; var b = region.Bounds;
                        Check(a.Right <= b.X || a.X >= b.Right || a.Bottom <= b.Y || a.Y >= b.Bottom);
                    }
            });
            Run("Activation automatically arranges all three external windows", () =>
            {
                var layout = controller.Layout(monitor);
                Equal(3, layout.Regions.Count); Equal(2, layout.Dividers.Count);
                VerifyBounds(layout, native);
            });
            Run("Dragging center swaps actual windows without losing any", () =>
            {
                var before = controller.Layout(monitor).Regions;
                var target = before.Single(r => r.Window.WindowId == fixtures[1].Id).Bounds;
                var source = before.Single(r => r.Window.WindowId == fixtures[0].Id).Bounds;
                controller.BeginDrag(fixtures[0].Id); controller.FinishDrag(new(target.X + target.Width / 2, target.Y + target.Height / 2)); Pump();
                Equal(source, controller.Layout(monitor).Regions.Single(r => r.Window.WindowId == fixtures[1].Id).Bounds);
                Equal(3, controller.Layout(monitor).Regions.Count); VerifyBounds(controller.Layout(monitor), native);
            });
            Run("Dragging to an edge splits and reflows actual windows", () =>
            {
                var target = controller.Layout(monitor).Regions.Single(r => r.Window.WindowId == fixtures[0].Id).Bounds;
                var point = new PixelPoint(target.X + target.Width / 2, target.Bottom - 12);
                controller.BeginDrag(fixtures[2].Id); controller.PreviewDrag(point);
                var originalBounds = fixtures.Select(w => native.VisibleBounds(w.Id)).ToArray();
                gestureTime += controller.Settings.SplitHoldMs - 1; controller.PreviewDrag(point);
                Equal(target, Application.Current!.Windows.OfType<DropPreviewWindow>().Single(w => w.IsVisible).PreviewBounds);
                gestureTime += 1; controller.PreviewDrag(point);
                Equal(SlotPreview.Bounds(target, Placement.Bottom, controller.Settings.Gap), Application.Current.Windows.OfType<DropPreviewWindow>().Single(w => w.IsVisible).PreviewBounds);
                for (int i = 0; i < fixtures.Length; i++) Equal(originalBounds[i], native.VisibleBounds(fixtures[i].Id));
                controller.FinishDrag(point); Pump();
                Equal(3, controller.Layout(monitor).Regions.Count); VerifyBounds(controller.Layout(monitor), native);
                var sourceBounds = controller.Layout(monitor).Regions.Single(r => r.Window.WindowId == fixtures[2].Id).Bounds;
                var targetBounds = controller.Layout(monitor).Regions.Single(r => r.Window.WindowId == fixtures[0].Id).Bounds;
                Equal(targetBounds.Bottom + controller.Settings.Gap, sourceBounds.Y); Equal(targetBounds.X, sourceBounds.X);
            });
            Run("Quick edge drop swaps without splitting before the hold threshold", () =>
            {
                var before = controller.Layout(monitor).Regions;
                var sourceBounds = before.Single(r => r.Window.WindowId == fixtures[0].Id).Bounds;
                var targetBounds = before.Single(r => r.Window.WindowId == fixtures[1].Id).Bounds;
                var point = new PixelPoint(targetBounds.X + 12, targetBounds.Y + targetBounds.Height / 2);
                controller.BeginDrag(fixtures[0].Id); controller.PreviewDrag(point); gestureTime += 100; controller.FinishDrag(point); Pump();
                Equal(sourceBounds, controller.Layout(monitor).Regions.Single(r => r.Window.WindowId == fixtures[1].Id).Bounds);
                VerifyBounds(controller.Layout(monitor), native);
            });
            Run("Moving a sibling highlights the old slot even when removal expands its final geometry", () =>
            {
                static SplitNode Pair(LayoutNode node) => node is SplitNode { First: WindowNode, Second: WindowNode } pair ? pair
                    : node is SplitNode split ? Pair(split.First is SplitNode ? split.First : split.Second) : throw new Exception("Missing sibling pair.");
                var pair = Pair(controller.DisplayState.Roots[monitor.Id]!);
                var source = (WindowNode)pair.First; var target = (WindowNode)pair.Second;
                var original = controller.Layout(monitor).Regions.Single(r => r.Window.Id == target.Id).Bounds;
                var point = pair.Axis == SplitAxis.Horizontal ? new PixelPoint(original.X + 8, original.Y + original.Height / 2)
                    : new PixelPoint(original.X + original.Width / 2, original.Y + 8);
                var placement = pair.Axis == SplitAxis.Horizontal ? Placement.Left : Placement.Top;
                controller.BeginDrag(source.WindowId); controller.PreviewDrag(point);
                gestureTime += controller.Settings.SplitHoldMs; controller.PreviewDrag(point);
                var shown = Application.Current!.Windows.OfType<DropPreviewWindow>().Single(w => w.IsVisible).PreviewBounds;
                Equal(SlotPreview.Bounds(original, placement, controller.Settings.Gap), shown);
                Check(shown != controller.Layout(monitor).Regions.Single(r => r.Window.Id == source.Id).Bounds);
                controller.CancelDrag();
            });
            Run("Wallpaper sampling reads the actual monitor through the Windows shell", () =>
            {
                var point = new PixelPoint(monitor.WorkArea.X + monitor.WorkArea.Width / 2, monitor.WorkArea.Y + monitor.WorkArea.Height / 2);
                var wallpaper = DesktopWallpaper.At(point);
                Check(wallpaper is not null && wallpaper.Monitor.Contains(point));
                Check(WallpaperContrast.At(point) == Brushes.Black || WallpaperContrast.At(point) == Brushes.White);
            });
            Run("Transition helpers close after motion completes", () =>
            { Pump(); Pump(); Check(!Application.Current!.Windows.Cast<Window>().Any(w => w.Title == "Bento transition")); });
            Run("All interface pages open and render without losing settings", () =>
            {
                var shell = new BentoWindow(controller); shell.Show();
                foreach (string page in new[] { "Workspace", "Gestures", "Updates", "Workspace" })
                { shell.SelectPage(page); shell.UpdateLayout(); CaptureWindow(shell, $"bento-{page.ToLowerInvariant()}.png"); }
                AppTheme.Apply("Dark"); shell.UpdateLayout(); CaptureWindow(shell,"bento-dark.png"); AppTheme.Apply("Light");
                shell.Close();
            });
            Run("Dark appearance gives headings and dropdowns light text", () =>
            {
                AppTheme.Apply("Dark"); var shell = new BentoWindow(controller); shell.Show(); shell.UpdateLayout();
                var text = (SolidColorBrush)Application.Current!.Resources["Text"];
                foreach (var label in Descendants<TextBlock>(shell).Where(t => t.Text is "Your workspace" or "Bento is active" or "Appearance" or "System"))
                    Equal(text.Color, ((SolidColorBrush)label.Foreground).Color);
                Equal(text.Color, ((SolidColorBrush)shell.Foreground).Color);
                shell.Close(); AppTheme.Apply("System");
            });
            Run("Dividers are non-topmost and only the related hover reveals its longer grip", () =>
            {
                var handles = Application.Current!.Windows.OfType<DesktopDividerWindow>().ToArray();
                foreach (var handle in handles)
                {
                    Check(!handle.Topmost);
                    var grip = (Border)((Grid)handle.Content).Children[0];
                    handle.RaiseEvent(new System.Windows.Input.MouseEventArgs(System.Windows.Input.Mouse.PrimaryDevice, 0) { RoutedEvent = UIElement.MouseLeaveEvent });
                    Equal(0d, grip.Opacity); Check(Math.Max(grip.Width, grip.Height) >= 40);
                }
                handles[0].RaiseEvent(new System.Windows.Input.MouseEventArgs(System.Windows.Input.Mouse.PrimaryDevice, 0) { RoutedEvent = UIElement.MouseEnterEvent });
                for (int i = 0; i < handles.Length; i++) Equal(i == 0 ? 1d : 0d, ((Border)((Grid)handles[i].Content).Children[0]).Opacity);
                handles[0].RaiseEvent(new System.Windows.Input.MouseEventArgs(System.Windows.Input.Mouse.PrimaryDevice, 0) { RoutedEvent = UIElement.MouseLeaveEvent });
                controller.ShowInterface(); Pump();
                Check(Application.Current.Windows.OfType<BentoWindow>().Single().IsActive);
                controller.Refresh();
                foreach (var handle in Application.Current.Windows.OfType<DesktopDividerWindow>()) Check(!handle.Topmost);
                Application.Current.Windows.OfType<BentoWindow>().Single().Close();
            });
            Run("Preview cancellation leaves external HWND unchanged", () =>
            {
                var before = fixtures.Select(w => native.VisibleBounds(w.Id)).ToArray();
                controller.BeginDrag(fixtures[0].Id); Pump(); controller.CancelDrag();
                for (int i = 0; i < 3; i++) Equal(before[i], native.VisibleBounds(fixtures[i].Id));
            });
            Run("Dragging shows only one destination preview and hides it after release", () =>
            {
                var target = controller.Layout(monitor).Regions.Single(r => r.Window.WindowId == fixtures[1].Id).Bounds;
                controller.BeginDrag(fixtures[0].Id); Pump();
                controller.PreviewDrag(new(target.X + target.Width / 2, target.Y + target.Height / 2));
                var previews = Application.Current!.Windows.OfType<DropPreviewWindow>().Where(w => w.IsVisible).ToArray();
                Equal(1, previews.Length); Equal(target, previews[0].PreviewBounds);
                Check(!Descendants<TextBlock>(previews[0]).Any()); Check(!Descendants<ProgressBar>(previews[0]).Any());
                if (OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22621) && !SystemParameters.HighContrast) Check(previews[0].AcrylicEnabled);
                previews[0].UpdateLayout();
                CapturePreview(previews[0], "drop-preview.png");
                controller.CancelDrag();
                Check(!previews[0].IsVisible);
            });
            Run("Pointer movement within one drop zone reuses the preview without moving HWNDs", () =>
            {
                var before = fixtures.Select(w => native.VisibleBounds(w.Id)).ToArray();
                var target = controller.Layout(monitor).Regions.Single(r => r.Window.WindowId == fixtures[1].Id).Bounds;
                var point = new PixelPoint(target.X + target.Width / 2, target.Y + target.Height / 2);
                controller.BeginDrag(fixtures[0].Id); controller.PreviewDrag(point);
                var first = controller.DisplayState;
                controller.PreviewDrag(new(point.X + 1, point.Y + 1));
                Check(ReferenceEquals(first, controller.DisplayState));
                for (int i = 0; i < 3; i++) Equal(before[i], native.VisibleBounds(fixtures[i].Id));
                controller.CancelDrag();
            });
            Run("Changing or leaving a drop zone invalidates its cached preview", () =>
            {
                var regions = controller.Layout(monitor).Regions;
                var target = regions.Single(r => r.Window.WindowId == fixtures[1].Id).Bounds;
                var other = regions.Single(r => r.Window.WindowId == fixtures[2].Id).Bounds;
                var point = new PixelPoint(target.X + target.Width / 2, target.Y + target.Height / 2);
                controller.BeginDrag(fixtures[0].Id); controller.PreviewDrag(point);
                var first = controller.DisplayState;
                controller.PreviewDrag(new(other.X + other.Width / 2, other.Y + other.Height / 2));
                Check(!ReferenceEquals(first, controller.DisplayState));
                controller.PreviewDrag(new(int.MinValue, int.MinValue));
                Check(!Application.Current!.Windows.OfType<DropPreviewWindow>().Any(w => w.IsVisible));
                controller.PreviewDrag(point);
                Check(!ReferenceEquals(first, controller.DisplayState));
                var fresh = controller.DisplayState;
                controller.CancelDrag(); controller.BeginDrag(fixtures[0].Id); controller.PreviewDrag(point);
                Check(!ReferenceEquals(fresh, controller.DisplayState));
                controller.CancelDrag();
            });
            Run("Divider commits native resize once gesture completes", () =>
            {
                var divider = controller.Layout(monitor).Dividers.First();
                controller.BeginDivider(monitor, divider);
                controller.FinishDrag(new(divider.ParentBounds.X + (int)(divider.ParentBounds.Width * .6), divider.ParentBounds.Y + 200)); Pump();
                VerifyBounds(controller.Layout(monitor), native);
            });
            Run("Resizing a real window edge resizes its neighboring regions", () =>
            {
                var before = controller.Layout(monitor);
                var boundary = before.Dividers.First();
                bool horizontal = boundary.Axis == SplitAxis.Horizontal;
                var source = before.Regions.First(r => horizontal ? r.Bounds.Right == boundary.Bounds.X : r.Bounds.Bottom == boundary.Bounds.Y);
                var requested = horizontal ? source.Bounds with { Width = source.Bounds.Width + 24 }
                    : source.Bounds with { Height = source.Bounds.Height + 24 };
                controller.BeginNativeResize(source.Window.WindowId);
                native.Move(source.Window.WindowId, requested);
                controller.FinishDrag(); Pump();
                var after = controller.Layout(monitor);
                Check(after.Regions.Single(r => r.Window.WindowId == source.Window.WindowId).Bounds != source.Bounds);
                VerifyBounds(after, native);
            });
            Run("Desktop undo and redo reapply geometry", () =>
            { controller.Undo(); Pump(); VerifyBounds(controller.Layout(monitor), native); controller.Redo(); Pump(); VerifyBounds(controller.Layout(monitor), native); });
            Process? extra = null;
            AppWindow? fourth = null;
            WindowSnapshot? fourthPlacement = null;
            Run("Newly opened window automatically joins the layout", () =>
            {
                var info = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true };
                info.ArgumentList.Add("--fixture"); info.ArgumentList.Add($"{prefix} 4");
                extra = Process.Start(info)!; processes.Add(extra);
                WaitForCount(controller, monitor, 4);
                fourth = controller.Windows.Single(w => w.Title == $"{prefix} 4");
                fourthPlacement = native.Capture(fourth.Id);
                VerifyBounds(controller.Layout(monitor), native);
            });
            Run("Unchanged membership preserves manual split ratios", () =>
            {
                var root = controller.DisplayState.Roots[monitor.Id];
                controller.Refresh(); Pump();
                Check(ReferenceEquals(root, controller.DisplayState.Roots[monitor.Id]));
            });
            Run("Minimized window leaves layout and stays minimized", () =>
            {
                Check(fourth is not null); native.Minimize(fourth!.Id);
                WaitForCount(controller, monitor, 3); Check(WindowCatalog.IsMinimized(fourth.Id));
                VerifyBounds(controller.Layout(monitor), native);
            });
            Run("Restored window automatically rejoins the layout", () =>
            { native.Restore(fourthPlacement!); WaitForCount(controller, monitor, 4); VerifyBounds(controller.Layout(monitor), native); });
            Run("Closing a dragged window clears preview and expands its neighbors", () =>
            {
                controller.BeginDrag(fourth!.Id);
                extra!.CloseMainWindow(); extra.WaitForExit(2000); WaitForCount(controller, monitor, 3);
                Check(!controller.Dragging); VerifyBounds(controller.Layout(monitor), native);
            });
            Run("Removing a real window expands its neighbor", () =>
            { controller.Remove(fixtures[2].Id); Pump(); Equal(2, controller.Layout(monitor).Regions.Count); VerifyBounds(controller.Layout(monitor), native); });
            Run("Released window stays floating until auto arrange all", () =>
            {
                controller.Refresh(); Equal(2, controller.Layout(monitor).Regions.Count);
                controller.AutoArrangeAll(); Pump(); Equal(3, controller.Layout(monitor).Regions.Count); VerifyBounds(controller.Layout(monitor), native);
            });
            Run("Restore all empties layout", () =>
            { controller.RestoreAll(); Pump(); Equal(0, controller.Layout(monitor).Regions.Count); });
            foreach (var original in originals) native.Restore(original);
        }
        catch (Exception ex) { Run("Native integration setup", () => throw new Exception("An interactive Windows desktop is required.", ex)); }
        finally
        {
            foreach (var process in processes)
            {
                try { if (!process.HasExited) { process.CloseMainWindow(); if (!process.WaitForExit(2000)) process.Kill(); } }
                finally { process.Dispose(); }
            }
        }
    }
    private static void VerifyBounds(LayoutResult layout, WindowController native)
    {
        foreach (var region in layout.Regions)
        {
            var actual = native.VisibleBounds(region.Window.WindowId); var expected = region.Bounds;
            if (Math.Abs(actual.X - expected.X) > 2 || Math.Abs(actual.Y - expected.Y) > 2 ||
                Math.Abs(actual.Width - expected.Width) > 2 || Math.Abs(actual.Height - expected.Height) > 2)
                throw new Exception($"Window {region.Window.WindowId}: expected {expected}; actual {actual}");
        }
    }
    private static IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
    {
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is T match) yield return match;
            foreach (var descendant in Descendants<T>(child)) yield return descendant;
        }
    }
    private static void WaitForCount(BentoController controller, DesktopMonitor monitor, int count)
    {
        var wait = Stopwatch.StartNew();
        while (wait.Elapsed < TimeSpan.FromSeconds(6))
        {
            Pump();
            if (controller.Layout(monitor).Regions.Count == count) return;
        }
        Equal(count, controller.Layout(monitor).Regions.Count);
    }
    private static void CapturePreview(DropPreviewWindow window, string name)
        => CaptureWindow(window, name);
    private static void CaptureWindow(Window window, string name)
    {
        var visual = (FrameworkElement)window.Content;
        var bitmap = new RenderTargetBitmap((int)visual.ActualWidth, (int)visual.ActualHeight, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        string output = Path.Combine(Directory.GetCurrentDirectory(), "artifacts", name);
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(output); encoder.Save(stream);
    }
    private static void Pump()
    {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(150) };
        timer.Tick += (_, _) => { timer.Stop(); frame.Continue = false; };
        timer.Start(); Dispatcher.PushFrame(frame);
    }
}
