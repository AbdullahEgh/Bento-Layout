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
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern nint GetWindow(nint handle, uint command);
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern nint WindowFromPoint(System.Drawing.Point point);
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern int GetWindowText(nint handle, System.Text.StringBuilder text, int length);
    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern nint GetWindowLongPtr(nint handle, int index);
    private static bool IsAbove(Window upper, Window lower)
    {
        nint target = new System.Windows.Interop.WindowInteropHelper(lower).Handle;
        for (nint next = GetWindow(new System.Windows.Interop.WindowInteropHelper(upper).Handle, 2); next != 0; next = GetWindow(next, 2))
            if (next == target) return true;
        return false;
    }
    internal static int Fixture(string title)
    {
        var app = new Application();
        app.Run(new Window { Title = title, Width = 640, Height = 480, MinWidth = 180, MinHeight = 120,
            Content = new TextBlock { Text = title, FontSize = 28, Margin = new Thickness(30) } });
        return 0;
    }
    internal static void SettingsOrderSmoke()
    {
        if (Application.Current is null)
        {
            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            app.Resources.MergedDictionaries.Add(new ResourceDictionary { Source = new Uri("pack://application:,,,/Bento;component/Theme.xaml") });
        }
        using var controller = new BentoController(() => [], new BentoSettings(ShortcutEnabled: false));
        controller.ShowInterface(); Pump();
        var settings = Application.Current!.Windows.OfType<BentoWindow>().Single();
        var other = new Window { Title = "Disposable foreground window", Width = 360, Height = 260 };
        try
        {
            other.Show(); other.Activate(); Pump();
            static IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
            {
                foreach (var child in LogicalTreeHelper.GetChildren(root).OfType<DependencyObject>())
                {
                    if (child is T match) yield return match;
                    foreach (var nested in Descendants<T>(child)) yield return nested;
                }
            }
            Run("Preferences save automatically while session layout has an explicit Save action", () =>
            {
                var names = Descendants<Button>(settings).Select(System.Windows.Automation.AutomationProperties.GetName).ToArray();
                Check(!names.Any(name => name is "Save" or "Save settings" or "Save preferences"));
                Check(names.Contains("Save for This Session"));
            });
            Run("Changing a setting saves automatically", () =>
            {
                var slider = Descendants<Slider>(settings).First();
                slider.Value = 12;
                var deadline = Stopwatch.StartNew();
                while (deadline.ElapsedMilliseconds < 1000 && controller.Settings.Gap != 12) { Pump(); Thread.Sleep(20); }
                Equal(12, controller.Settings.Gap);
            });
            Run("Settings adapt to a phone-width window without losing navigation", () =>
            {
                settings.Width = 360; settings.Height = 600; Pump();
                var picker = Descendants<ComboBox>(settings).Single(c => System.Windows.Automation.AutomationProperties.GetName(c) == "Settings page");
                Check(picker.IsVisible); Check(settings.ActualWidth <= 361);
                picker.SelectedItem = "Gestures"; Pump();
                Check(Descendants<TextBox>(settings).Any(t => System.Windows.Automation.AutomationProperties.GetName(t) == "Shortcut keys"));
                picker.SelectedItem = "Workspace"; Pump();
                foreach (var control in Descendants<Slider>(settings))
                {
                    var point = control.TransformToAncestor(settings).Transform(new Point(0, 0));
                    Check(point.X >= 0 && point.X + control.ActualWidth <= settings.ActualWidth);
                }
                settings.Width = 850; Pump(); Check(!picker.IsVisible);
            });
            Run("Settings are not topmost", () => Check(!settings.Topmost));
            Run("Foreground fixture starts above settings", () => Check(IsAbove(other, settings)));
            for (int i = 0; i < 3; i++) { controller.Refresh(); Pump(); }
            Run("Desktop refresh keeps settings behind another window", () => Check(IsAbove(other, settings)));
        }
        finally { other.Close(); settings.Close(); }
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
            var preBentoBounds = fixtures.Select(w => native.VisibleBounds(w.Id)).ToArray();
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
                var all = ResizeHandles.Calculate(controller.DisplayState.Roots[monitor.Id]!, controller.Area(monitor), controller.Gap(monitor));
                Equal(all.Count(h => ResizeHandles.IsUniversal(h, all)), handles.Length);
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
                Equal(controller.Layout(monitor).Regions.Single(r => r.Window.WindowId == fixtures[2].Id).Bounds, Application.Current.Windows.OfType<DropPreviewWindow>().Single(w => w.IsVisible).PreviewBounds);
                for (int i = 0; i < fixtures.Length; i++) Equal(originalBounds[i], native.VisibleBounds(fixtures[i].Id));
                controller.FinishDrag(point); Pump();
                Equal(3, controller.Layout(monitor).Regions.Count); VerifyBounds(controller.Layout(monitor), native);
                var sourceBounds = controller.Layout(monitor).Regions.Single(r => r.Window.WindowId == fixtures[2].Id).Bounds;
                var targetBounds = controller.Layout(monitor).Regions.Single(r => r.Window.WindowId == fixtures[0].Id).Bounds;
                Equal(targetBounds.Bottom + controller.Gap(monitor), sourceBounds.Y); Equal(targetBounds.X, sourceBounds.X);
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
            Run("Moving a sibling previews its final geometry after source removal", () =>
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
                Equal(controller.Layout(monitor).Regions.Single(r => r.Window.Id == source.Id).Bounds, shown);
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
                    Equal(0d, (double)grip.GetAnimationBaseValue(UIElement.OpacityProperty)); Check(Math.Max(grip.Width, grip.Height) >= 40);
                }
                handles[0].RaiseEvent(new System.Windows.Input.MouseEventArgs(System.Windows.Input.Mouse.PrimaryDevice, 0) { RoutedEvent = UIElement.MouseEnterEvent });
                for (int i = 0; i < handles.Length; i++) Equal(i == 0 ? 1d : 0d, (double)((Border)((Grid)handles[i].Content).Children[0]).GetAnimationBaseValue(UIElement.OpacityProperty));
                handles[0].RaiseEvent(new System.Windows.Input.MouseEventArgs(System.Windows.Input.Mouse.PrimaryDevice, 0) { RoutedEvent = UIElement.MouseLeaveEvent });
                controller.ShowInterface(); Pump();
                Check(Application.Current.Windows.OfType<BentoWindow>().Single().IsActive);
                controller.Refresh();
                for (int i = 0; i < 8; i++) Pump(); // Includes the periodic background re-stack.
                foreach (var handle in Application.Current.Windows.OfType<DesktopDividerWindow>())
                {
                    Check(!handle.Topmost);
                    Check(IsAbove(Application.Current.Windows.OfType<BentoWindow>().Single(), handle));
                    Check(IsAbove(handle, Application.Current.Windows.OfType<DesktopBackdropWindow>().Single()));
                }
                Application.Current.Windows.OfType<BentoWindow>().Single().Close();
            });
            Run("Grabbers remain below applications and above the background", () =>
            {
                controller.ShowInterface();
                var settingsWindow = Application.Current!.Windows.OfType<BentoWindow>().Single();
                settingsWindow.WindowState = WindowState.Minimized;
                foreach (var fixture in fixtures) DesktopIntegration.RaiseOverlay((nint)fixture.Id);
                controller.Refresh(); Pump();
                foreach (var handle in Application.Current!.Windows.OfType<DesktopDividerWindow>())
                {
                    var bounds = handle.DesktopBounds;
                    var expected = new System.Windows.Interop.WindowInteropHelper(handle).Handle;
                    var backdrop = Application.Current.Windows.OfType<DesktopBackdropWindow>().First();
                    Check(IsAbove(handle, backdrop));
                    foreach (var fixture in fixtures)
                    {
                        bool belowApplication = false;
                        for (nint next = GetWindow((nint)fixture.Id, 2); next != 0; next = GetWindow(next, 2))
                            if (next == expected) { belowApplication = true; break; }
                        Check(belowApplication);
                    }
                }
                settingsWindow.Close();
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
            Run("Returning to a drop zone reuses its gesture cache; a new gesture invalidates it", () =>
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
                Check(ReferenceEquals(first, controller.DisplayState));
                var fresh = controller.DisplayState;
                controller.CancelDrag(); controller.BeginDrag(fixtures[0].Id); controller.PreviewDrag(point);
                Check(!ReferenceEquals(fresh, controller.DisplayState));
                controller.CancelDrag();
            });
            Run("Moving a divider preserves its stacking position before any controller repair", () =>
            {
                controller.Refresh();
                var handle = Application.Current!.Windows.OfType<DesktopDividerWindow>().First();
                nint hwnd = new System.Windows.Interop.WindowInteropHelper(handle).Handle;
                nint above = GetWindow(hwnd, 3), below = GetWindow(hwnd, 2);
                var bounds = handle.DesktopBounds;
                handle.PresentResize(new(bounds.X + 10, bounds.Y + 10, bounds.Width, bounds.Height));
                Equal(above, GetWindow(hwnd, 3)); Equal(below, GetWindow(hwnd, 2));
                handle.ResetPresentation();
                Equal(above, GetWindow(hwnd, 3)); Equal(below, GetWindow(hwnd, 2));
            });
            Run("Divider commits native resize once gesture completes", () =>
            {
                var divider = controller.Layout(monitor).Dividers.First();
                controller.BeginDivider(monitor, divider, new(divider.Bounds.X + 1, divider.Bounds.Y + 1));
                controller.FinishDrag(new(divider.ParentBounds.X + (int)(divider.ParentBounds.Width * .6), divider.ParentBounds.Y + 200)); Pump();
                VerifyBounds(controller.Layout(monitor), native);
            });
            Run("Divider drag resizes applications live with an 80-DIP same-width grabber and cancellation restores them", () =>
            {
                var before = fixtures.Select(w => native.VisibleBounds(w.Id)).ToArray();
                var boundary = controller.Layout(monitor).Dividers.First();
                controller.BeginDivider(monitor, boundary, new(boundary.Bounds.X + 1, boundary.Bounds.Y + 1));
                var point = new PixelPoint(boundary.ParentBounds.X + boundary.ParentBounds.Width / 2, boundary.ParentBounds.Y + boundary.ParentBounds.Height / 2);
                controller.PreviewDrag(point);
                Check(!Application.Current!.Windows.OfType<DropPreviewWindow>().Any(w => w.IsVisible));
                var active = Application.Current.Windows.OfType<DesktopDividerWindow>().Single(w => w.IsVisible);
                var grip = (Border)((Grid)active.Content).Children[0];
                Equal(80d, Math.Max((double)grip.GetAnimationBaseValue(FrameworkElement.WidthProperty), (double)grip.GetAnimationBaseValue(FrameworkElement.HeightProperty)));
                Equal(2d, Math.Min(grip.Width, grip.Height)); Equal(1d, (double)grip.GetAnimationBaseValue(UIElement.OpacityProperty));
                Equal(controller.Layout(monitor).Dividers.Single(d => d.SplitId == boundary.SplitId).Bounds, native.VisibleBounds(new System.Windows.Interop.WindowInteropHelper(active).Handle.ToInt64()));
                VerifyBounds(controller.Layout(monitor), native);
                Check(fixtures.Where((w, i) => native.VisibleBounds(w.Id) != before[i]).Any());
                controller.CancelDrag(); Equal(80d, Math.Max((double)grip.GetAnimationBaseValue(FrameworkElement.WidthProperty), (double)grip.GetAnimationBaseValue(FrameworkElement.HeightProperty)));
                for (int i = 0; i < fixtures.Length; i++) Equal(before[i], native.VisibleBounds(fixtures[i].Id));
                Equal(boundary.Bounds, native.VisibleBounds(new System.Windows.Interop.WindowInteropHelper(active).Handle.ToInt64()));
            });
            Run("Grabber retains its fixed specific length and retains its window on release", () =>
            {
                var boundary = controller.Layout(monitor).Dividers.First();
                var point = new PixelPoint(boundary.Bounds.X + boundary.Bounds.Width / 2, boundary.Bounds.Y + boundary.Bounds.Height / 2);
                var handle = Application.Current!.Windows.OfType<DesktopDividerWindow>().Single(w => w.SplitId == boundary.SplitId);
                controller.BeginDivider(monitor, boundary, point); Pump(); Pump();
                var grip = (Border)((Grid)handle.Content).Children[0];
                Equal(80d, Math.Max(grip.Width, grip.Height)); Equal(2d, Math.Min(grip.Width, grip.Height));
                controller.FinishDrag(point); Pump(); Pump();
                Check(ReferenceEquals(handle, Application.Current.Windows.OfType<DesktopDividerWindow>().Single(w => w.SplitId == boundary.SplitId)));
                Equal(80d, Math.Max(grip.Width, grip.Height));
            });
            Run("Turning Bento off restores the pre-Bento positions and on resumes the edited split", () =>
            {
                var bentoBounds = fixtures.Select(w => native.VisibleBounds(w.Id)).ToArray();
                controller.ToggleBento(); Pump(); Check(!controller.Automatic);
                for (int i = 0; i < fixtures.Length; i++) Equal(preBentoBounds[i], native.VisibleBounds(fixtures[i].Id));
                Check(!Application.Current!.Windows.OfType<DesktopDividerWindow>().Any(w => w.IsVisible));
                controller.ToggleBento(); Pump(); Check(controller.Automatic);
                for (int i = 0; i < fixtures.Length; i++) Equal(bentoBounds[i], native.VisibleBounds(fixtures[i].Id));
            });
            Run("Each activation remembers the user's latest floating window positions", () =>
            {
                controller.SetAutomatic(false); Pump();
                var moved = new PixelRect(monitor.WorkArea.X + 40, monitor.WorkArea.Y + 40, 500, 350);
                native.Move(fixtures[0].Id, moved);
                controller.SetAutomatic(true); Pump(); controller.SetAutomatic(false); Pump();
                Equal(moved, native.VisibleBounds(fixtures[0].Id));
                controller.SetAutomatic(true); Pump(); VerifyBounds(controller.Layout(monitor), native);
            });
            Run("Desktop background dims the usable area and supports clear, half and full darkness", () =>
            {
                var backdrop = Application.Current!.Windows.OfType<DesktopBackdropWindow>().Single(w => w.IsVisible);
                var shade = (Border)backdrop.Content;
                Equal(.5d, shade.Opacity); Check(!backdrop.IsHitTestVisible); Check(!backdrop.ShowActivated);
                var handle = new System.Windows.Interop.WindowInteropHelper(backdrop).Handle;
                Equal(monitor.WorkArea, native.VisibleBounds(handle.ToInt64()));
                var applications = fixtures.Select(w => w.Id).ToArray();
                backdrop.Present(monitor, 0, applications); Check(!backdrop.IsVisible);
                backdrop.Present(monitor, 100, applications); Check(backdrop.IsVisible); Equal(1d, shade.Opacity);
                backdrop.Present(monitor, 50, applications); Equal(.5d, shade.Opacity);
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
            Run("Closing a sibling invalidates an incoming drag proposal", () =>
            {
                controller.BeginDrag(fixtures[0].Id);
                var target = controller.Layout(monitor).Regions.Single(r => r.Window.WindowId == fixtures[1].Id).Bounds;
                var point = new PixelPoint(target.X + 2, target.Y + target.Height / 2);
                controller.PreviewDrag(point);
                extra!.CloseMainWindow(); extra.WaitForExit(2000); Pump();
                controller.PreviewDrag(point); controller.FinishDrag(point); WaitForCount(controller, monitor, 3);
                Check(controller.DisplayState.Windows.All(w => w.WindowId != fourth!.Id)); VerifyBounds(controller.Layout(monitor), native);
                var info = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true };
                info.ArgumentList.Add("--fixture"); info.ArgumentList.Add($"{prefix} 4");
                extra = Process.Start(info)!; processes.Add(extra); WaitForCount(controller, monitor, 4);
                fourth = controller.Windows.Single(w => w.Title == $"{prefix} 4");
            });
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
            Run("Pause holds membership; resume minimizes a new floating fixture until it is restored", () =>
            {
                bool includeThird = false;
                using var paused = new BentoController(() => WindowCatalog.Discover(includeMinimized: false)
                    .Where(w => fixtures.Take(includeThird ? 3 : 2).Any(f => f.Id == w.Id)).ToArray(), new BentoSettings(Animate: false, ShortcutEnabled: false));
                paused.AutoArrangeAll(); Pump();
                var frames = fixtures.Take(2).Select(w => native.VisibleBounds(w.Id)).ToArray();
                paused.SetPaused(true); Pump(); Check(paused.Paused);
                Check(Application.Current!.Windows.Cast<Window>().Where(w => w.Title == "Bento paused window").All(w => !w.IsHitTestVisible && !w.ShowActivated));
                includeThird = true; paused.Refresh(); Equal(2, paused.ManagedCount);
                DesktopIntegration.PlaceAboveApplication((nint)fixtures[2].Id, fixtures[0].Id);
                paused.SetPaused(false); Pump(); Check(!paused.Paused); Check(WindowCatalog.IsMinimized(fixtures[2].Id));
                Check(frames.SequenceEqual(fixtures.Take(2).Select(w => native.VisibleBounds(w.Id))));
                native.Restore(originals[2]); paused.Refresh(); Pump(); Equal(3, paused.ManagedCount);
                paused.RestoreAll(); Pump();
            });
            Run("Desktop switch during grip invalidates stale release and leaves the new desktop off", () =>
            {
                var a = Guid.NewGuid(); var b = Guid.NewGuid(); var desktops = new FixtureDesktops { Current = a };
                foreach (var window in fixtures.Take(2)) desktops.Owners[window.Id] = a;
                desktops.Owners[fixtures[2].Id] = b;
                using var scoped = new BentoController(() => WindowCatalog.Discover(includeMinimized: false)
                    .Where(w => fixtures.Any(f => f.Id == w.Id)).ToArray(), new BentoSettings(Animate: false, ShortcutEnabled: false), desktopEnvironment: desktops);
                scoped.AutoArrangeAll(); Pump(); Equal(2, scoped.ManagedCount);
                var seam = scoped.Layout(monitor).Dividers.Single();
                var press = new PixelPoint(seam.Bounds.X + seam.Bounds.Width / 2, seam.Bounds.Y + seam.Bounds.Height / 2);
                scoped.BeginDivider(monitor, seam, press); scoped.PreviewDrag(new(press.X + 35, press.Y + 35));
                var held = fixtures.Take(2).Select(w => native.VisibleBounds(w.Id)).ToArray();
                desktops.Current = b; scoped.CheckDesktopContext(); Check(!scoped.Automatic); Equal(0, scoped.ManagedCount);
                scoped.FinishDrag(press); scoped.CancelDrag(); Pump();
                Check(held.SequenceEqual(fixtures.Take(2).Select(w => native.VisibleBounds(w.Id))));
                scoped.AutoArrangeAll(); Equal(1, scoped.ManagedCount);
                var bFrame = native.VisibleBounds(fixtures[2].Id);
                desktops.Current = a; scoped.CheckDesktopContext(); scoped.Refresh(); Pump(); Check(scoped.Automatic); Equal(2, scoped.ManagedCount);
                Equal(bFrame, native.VisibleBounds(fixtures[2].Id));
                scoped.RestoreAll(); desktops.Current = b; scoped.CheckDesktopContext(); scoped.RestoreAll(); Pump();
            });
            Run("Fullscreen member retains a return slot without native writes to its fixture", () =>
            {
                var desktop = Guid.NewGuid(); var desktops = new FixtureDesktops { Current = desktop };
                foreach (var window in fixtures) desktops.Owners[window.Id] = desktop;
                using var reserved = new BentoController(() => WindowCatalog.Discover(includeMinimized: false)
                    .Where(w => fixtures.Any(f => f.Id == w.Id)).ToArray(), new BentoSettings(Animate: false, ShortcutEnabled: false), desktopEnvironment: desktops);
                reserved.AutoArrangeAll(); Pump();
                var before = fixtures.Select(w => native.VisibleBounds(w.Id)).ToArray();
                var presentation = monitor.Bounds; native.Move(fixtures[0].Id, presentation);
                desktops.Full.Add(fixtures[0].Id); reserved.Refresh(); Pump();
                Equal(presentation, native.VisibleBounds(fixtures[0].Id)); Equal(2, reserved.ManagedCount);
                desktops.Full.Clear(); native.Move(fixtures[0].Id, before[0]); reserved.Refresh(); Pump(); Equal(3, reserved.ManagedCount);
                Check(before.SequenceEqual(fixtures.Select(w => native.VisibleBounds(w.Id))));
                desktops.Suspended = true; reserved.Refresh(); reserved.AutoArrangeAll();
                Check(before.SequenceEqual(fixtures.Select(w => native.VisibleBounds(w.Id))));
                desktops.Suspended = false; reserved.CheckDesktopContext(); reserved.Refresh(); reserved.RestoreAll(); Pump();
            });
            Run("Overflow minimizes and taskbar restore reinserts a window", () =>
            {
                bool oversized = true;
                using var overflow = new BentoController(() => WindowCatalog.Discover(includeMinimized: false)
                    .Where(w => fixtures.Any(f => f.Id == w.Id)).Select(w => oversized && w.Id == fixtures[0].Id
                        ? w with { Minimum = new PixelSize(monitor.WorkArea.Width + 100, 120) } : w).ToArray(),
                    new BentoSettings(Animate: false, ShortcutEnabled: false));
                overflow.AutoArrangeAll(); Pump();
                Equal(2, overflow.ManagedCount); Check(WindowCatalog.IsMinimized(fixtures[0].Id)); Equal(1, overflow.MinimizedCount);
                oversized = false; native.Restore(originals[0]); overflow.Refresh(); Pump();
                Equal(3, overflow.ManagedCount); Equal(0, overflow.MinimizedCount); VerifyBounds(overflow.Layout(monitor), native);
                overflow.RestoreAll(); Pump(); Check(!WindowCatalog.IsMinimized(fixtures[0].Id));
                native.Minimize(fixtures[0].Id); overflow.AutoArrangeAll(); overflow.RestoreAll(); Pump();
                Check(WindowCatalog.IsMinimized(fixtures[0].Id)); native.Restore(originals[0]);
            });
            Run("Session save keeps Off geometry; explicit Restore still restores originals", () =>
            {
                using var session = new BentoController(() => WindowCatalog.Discover(includeMinimized: false)
                    .Where(w => fixtures.Any(f => f.Id == w.Id)).ToArray(), new BentoSettings(Animate: false, ShortcutEnabled: false));
                session.AutoArrangeAll(); Pump(); session.SaveBento(); Check(session.HasSessionSave);
                var saved = fixtures.Select(w => native.VisibleBounds(w.Id)).ToArray();
                session.SetAutomatic(false); Pump(); Check(!session.Automatic);
                Check(saved.SequenceEqual(fixtures.Select(w => native.VisibleBounds(w.Id))));
                session.UseSessionSave(); Pump(); Check(session.Automatic);
                Check(saved.SequenceEqual(fixtures.Select(w => native.VisibleBounds(w.Id))));
                session.SetAutomatic(false); session.RestoreAll(); Pump();
                foreach (var original in originals) Equal(original.VisibleBounds, native.VisibleBounds(original.WindowId));
                session.ClearSessionSave(); Check(!session.HasSessionSave);
            });
            foreach (bool liveResize in new[] { false, true })
                Run($"Quit preserves native frames and overflow (live resize: {liveResize})", () =>
                {
                    using var quitting = new BentoController(() => WindowCatalog.Discover(includeMinimized: false)
                        .Where(w => fixtures.Any(f => f.Id == w.Id)).Select(w => w.Id == fixtures[0].Id
                            ? w with { Minimum = new PixelSize(monitor.WorkArea.Width + 100, 120) } : w).ToArray(),
                        new BentoSettings(Animate: false, ShortcutEnabled: false));
                    quitting.AutoArrangeAll(); Pump();
                    Check(WindowCatalog.IsMinimized(fixtures[0].Id));
                    var arranged = fixtures.Skip(1).Select(w => native.VisibleBounds(w.Id)).ToArray();
                    if (liveResize)
                    {
                        var seam = quitting.Layout(monitor).Dividers.Single();
                        var press = new PixelPoint(seam.Bounds.X + seam.Bounds.Width / 2, seam.Bounds.Y + seam.Bounds.Height / 2);
                        quitting.BeginDivider(monitor, seam, press);
                        quitting.PreviewDrag(new(press.X + 24, press.Y + 24));
                        Check(quitting.Dragging);
                    }
                    var before = fixtures.Skip(1).Select(w => native.VisibleBounds(w.Id)).ToArray();
                    if (liveResize) Check(!arranged.SequenceEqual(before));
                    quitting.Dispose();
                    // Queued callbacks and capture loss must stay inert after disposal.
                    quitting.CancelDrag(); quitting.Refresh(); quitting.FinishDrag(); quitting.Dispose(); Pump();
                    Check(WindowCatalog.IsMinimized(fixtures[0].Id));
                    Check(before.SequenceEqual(fixtures.Skip(1).Select(w => native.VisibleBounds(w.Id))));
                    foreach (var original in originals) native.Restore(original);
                });
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
    private sealed class FixtureDesktops : IDesktopEnvironment
    {
        public Guid Current;
        public bool Suspended;
        public readonly Dictionary<long, Guid> Owners = new();
        public readonly HashSet<long> Full = new();
        public DesktopObservation Sample() => new(Current, Suspended, Suspended ? "Fixture transition" : null);
        public bool IsCurrent(Guid desktop) => !Suspended && Current == desktop;
        public bool Contains(Guid desktop, long window) => IsCurrent(desktop) && Owners.GetValueOrDefault(window) == desktop;
        public bool Fullscreen(long window) => Full.Contains(window);
        public bool MoveHelper(long window, Guid desktop) => IsCurrent(desktop);
        public void Dispose() { }
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
