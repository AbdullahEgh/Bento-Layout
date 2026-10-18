using System.Threading;
using System.Windows.Threading;

namespace Bento.UI;

public partial class App : Application
{
    private Mutex? instance;
    private BentoController? controller;
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        instance = new Mutex(true, @"Local\Bento.Windows.SingleInstance", out bool created);
        if (!created) { Shutdown(); return; }
        DispatcherUnhandledException += (_, args) =>
        {
            args.Handled = true;
            controller?.Report(args.Exception.Message);
        };
        try
        {
            controller = e.Args.Contains("--smoke") ? new BentoController(() => []) : new BentoController();
            AppTheme.Apply(controller.Settings.Theme);
            if (controller.Settings.OnboardingComplete || e.Args.Contains("--smoke") || e.Args.Contains("--login")) controller.ArrangeDesktop();
            if (!e.Args.Contains("--smoke"))
            {
                if (!e.Args.Contains("--login")) controller.ShowInterface(!controller.Settings.OnboardingComplete ? "Welcome" : e.Args.Contains("--updates") ? "Updates" : "Workspace");
                if (controller.Settings.CheckUpdates && !string.IsNullOrWhiteSpace(controller.Settings.UpdateRepository)) _ = CheckForUpdates();
            }
            if (e.Args.Contains("--smoke"))
            {
                var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
                timer.Tick += (_, _) => { timer.Stop(); Shutdown(); };
                timer.Start();
            }
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, "Bento", MessageBoxButton.OK, MessageBoxImage.Error); Shutdown(1); }
    }
    private async System.Threading.Tasks.Task CheckForUpdates()
    {
        try
        {
            var update = await new UpdateService().CheckAsync(controller!.Settings.UpdateRepository);
            if (update is not null) controller.Report($"Bento {update.Version} is available. Open Updates to review and install.");
        }
        catch { /* Offline startup stays quiet; explicit checks display actionable errors. */ }
    }
    public void ShutdownKeepingWindows()
    {
        controller?.Dispose(); // Run before WPF closes Settings and flushes its draft.
        Shutdown();
    }
    protected override void OnSessionEnding(SessionEndingCancelEventArgs e)
    {
        base.OnSessionEnding(e);
        if (!e.Cancel) controller?.Dispose();
    }
    protected override void OnExit(ExitEventArgs e)
    {
        controller?.Dispose();
        instance?.Dispose();
        base.OnExit(e);
    }
}
