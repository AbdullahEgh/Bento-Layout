using System.Text.Json;
using System.Windows.Automation;
using System.Windows.Threading;
using Microsoft.Win32;

namespace Bento.UI;

public sealed class BentoWindow : Window
{
    private readonly BentoController controller;
    private readonly StackPanel content = new();
    private readonly ScrollViewer scroll = new();
    private readonly Dictionary<string, Button> navigation = new();
    private TextBlock status = new(), count = new();
    private Button? pause;
    private readonly TextBlock feedback = new();
    private readonly DispatcherTimer refresh = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly DispatcherTimer autoSave = new() { Interval = TimeSpan.FromMilliseconds(350) };
    private bool pendingSave;
    private BentoSettings draft;
    private string page = "Workspace";
    private bool busy;
    private bool? draftStartAtLogin;
    private readonly System.Threading.CancellationTokenSource lifetime = new();

    public BentoWindow(BentoController controller)
    {
        this.controller = controller; draft = controller.Settings;
        Title = "Bento"; Icon = AppIcons.Image; Width = 850; Height = 650; MinWidth = 740; MinHeight = 540; Topmost = false;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        SetResourceReference(BackgroundProperty, "Page");
        SetResourceReference(ForegroundProperty, "Text");
        FontFamily = new FontFamily("Segoe UI Variable, Segoe UI"); FontSize = 13;
        void UpdateCaption() => WindowAppearance.SetDarkCaption(new System.Windows.Interop.WindowInteropHelper(this).Handle, AppTheme.IsDark);
        SourceInitialized += (_, _) => UpdateCaption();
        AppTheme.Changed += UpdateCaption;
        Closed += (_, _) => AppTheme.Changed -= UpdateCaption;
        var root = new Grid(); root.SetResourceReference(Panel.BackgroundProperty, "Page"); root.ColumnDefinitions.Add(new() { Width = new GridLength(190) }); root.ColumnDefinitions.Add(new());
        var sidebar = new Border { Padding = new Thickness(16, 26, 16, 18) }; sidebar.SetResourceReference(Border.BackgroundProperty, "Sidebar");
        var side = new DockPanel(); sidebar.Child = side;
        var identity = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(6, 0, 0, 32) };
        identity.Children.Add(new Image { Source = AppIcons.Image, Width = 38, Height = 38, Margin = new Thickness(0, 0, 10, 0) });
        identity.Children.Add(new TextBlock { Text = "Bento", FontSize = 24, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });
        DockPanel.SetDock(identity, Dock.Top); side.Children.Add(identity);
        var version = Label($"Bento {UpdateService.CurrentVersion}\nMade for your desktop.", true); version.Margin = new Thickness(8, 0, 0, 0);
        DockPanel.SetDock(version, Dock.Bottom); side.Children.Add(version);
        var nav = new StackPanel();
        foreach (string name in new[] { "Workspace", "Gestures", "Updates", "What's New" })
        {
            var caption = new StackPanel { Orientation = Orientation.Horizontal }; caption.Children.Add(Symbols.Create(name));
            caption.Children.Add(new TextBlock { Text = name, Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
            var button = new Button { Content = caption, Margin = new Thickness(0, 0, 0, 5), BorderThickness = new Thickness(0), HorizontalContentAlignment = HorizontalAlignment.Left };
            button.Click += (_, _) => SelectPage(name); AutomationProperties.SetName(button, name); navigation[name] = button; nav.Children.Add(button);
        }
        side.Children.Add(nav); root.Children.Add(sidebar);
        var main = new Grid { Margin = new Thickness(32, 28, 32, 22) }; Grid.SetColumn(main, 1);
        main.RowDefinitions.Add(new()); main.RowDefinitions.Add(new() { Height = GridLength.Auto });
        scroll.Content = content; scroll.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        scroll.HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled; scroll.Padding = new Thickness(0, 0, 8, 0);
        main.Children.Add(scroll);
        var footer = new DockPanel { Margin = new Thickness(0, 18, 0, 0), LastChildFill = true };
        feedback.FontSize = 12; feedback.VerticalAlignment = VerticalAlignment.Center; feedback.Margin = new Thickness(0, 0, 12, 0); feedback.SetResourceReference(TextBlock.ForegroundProperty, "Secondary");
        footer.Children.Add(feedback); Grid.SetRow(footer, 1); main.Children.Add(footer); root.Children.Add(main); Content = root;
        autoSave.Tick += (_, _) => { autoSave.Stop(); if (pendingSave) Save(); };
        Closing += (_, _) => { autoSave.Stop(); if (pendingSave) Save(); };
        refresh.Tick += (_, _) => RefreshWorkspaceStatus();
        refresh.Start(); Closed += (_, _) => { refresh.Stop(); lifetime.Cancel(); };
        SelectPage("Workspace");
    }
    public void SelectPage(string name)
    {
        if (busy) return;
        page = name; content.Children.Clear(); scroll.ScrollToTop();
        bool reading = name is "What's New" or "Update Log";
        feedback.Visibility = reading ? Visibility.Collapsed : Visibility.Visible;
        foreach (var (key, button) in navigation) button.SetResourceReference(BackgroundProperty, key == (name == "Update Log" ? "What's New" : name) ? "Selection" : "Sidebar");
        switch (name) { case "Gestures": Gestures(); break; case "Updates": Updates(); break; case "What's New": WhatsNew(); break; case "Update Log": UpdateLog(); break; default: Workspace(); break; }
    }
    private static TextBlock Label(string text, bool secondary = false)
    {
        var label = new TextBlock { Text = text, LineHeight = 19, TextWrapping = TextWrapping.Wrap };
        if (secondary) label.SetResourceReference(TextBlock.ForegroundProperty, "Secondary");
        return label;
    }
    private void Heading(string title, string detail)
    {
        content.Children.Add(new TextBlock { Text = title, FontSize = 28, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 5) });
        var subtitle = Label(detail, true); subtitle.Margin = new Thickness(0, 0, 0, 24); content.Children.Add(subtitle);
    }
    private StackPanel Card(string? title = null)
    {
        if (title is not null) content.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold, Margin = new Thickness(2, 6, 0, 9) });
        var rows = new StackPanel(); var border = new Border { CornerRadius = new CornerRadius(12), BorderThickness = new Thickness(1), Padding = new Thickness(16, 3, 16, 3), Margin = new Thickness(0, 0, 0, 18), Child = rows };
        border.SetResourceReference(Border.BackgroundProperty, "Surface"); border.SetResourceReference(Border.BorderBrushProperty, "Line"); content.Children.Add(border); return rows;
    }
    private static void Row(StackPanel parent, string title, string description, FrameworkElement control)
    {
        if (parent.Children.Count > 0) { var line = new Border { Height = 1 }; line.SetResourceReference(Border.BackgroundProperty, "Line"); parent.Children.Add(line); }
        var row = new Grid { Margin = new Thickness(0, 13, 0, 13) }; row.ColumnDefinitions.Add(new()); row.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        var labels = new StackPanel { Margin = new Thickness(0, 0, 18, 0), VerticalAlignment = VerticalAlignment.Center };
        labels.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.Medium });
        if (description.Length > 0) { var note = Label(description, true); note.FontSize = 12; note.Margin = new Thickness(0, 4, 0, 0); labels.Children.Add(note); }
        var caption = new DockPanel();
        var icon = Symbols.Create(title, 20); icon.Margin = new Thickness(0, 0, 12, 0); icon.VerticalAlignment = VerticalAlignment.Center; icon.IsHitTestVisible = false;
        DockPanel.SetDock(icon, Dock.Left); caption.Children.Add(icon); caption.Children.Add(labels);
        row.Children.Add(caption); Grid.SetColumn(control, 1); control.VerticalAlignment = VerticalAlignment.Center; row.Children.Add(control);
        AutomationProperties.SetName(control, title); parent.Children.Add(row);
    }
    private CheckBox Toggle(bool value, Action<bool> changed)
    {
        var toggle = new CheckBox { IsChecked = value };
        toggle.Checked += (_, _) => { changed(true); Dirty(); }; toggle.Unchecked += (_, _) => { changed(false); Dirty(); }; return toggle;
    }
    private FrameworkElement Range(int value, int min, int max, int step, string unit, Action<int> changed)
    {
        var panel = new StackPanel { Width = 160 };
        var caption = Label($"{value}{unit}", true); caption.HorizontalAlignment = HorizontalAlignment.Right; caption.FontSize = 12;
        var slider = new Slider { Minimum = min, Maximum = max, TickFrequency = step, Value = value };
        slider.ValueChanged += (_, _) => { int n = (int)Math.Round(slider.Value); caption.Text = $"{n}{unit}"; changed(n); Dirty(); };
        panel.Children.Add(caption); panel.Children.Add(slider); return panel;
    }
    private void Dirty()
    {
        pendingSave = true; feedback.Text = "Saving…";
        autoSave.Stop(); autoSave.Start();
    }
    private bool Save()
    {
        try
        {
            if (!string.IsNullOrWhiteSpace(draft.UpdateRepository)) draft = draft with { UpdateRepository = UpdateService.NormalizeRepository(draft.UpdateRepository) };
            if (!controller.UpdateSettings(draft)) { feedback.Text = controller.Status; return false; }
            if (draftStartAtLogin is bool startAtLogin) { LoginStartup.SetEnabled(startAtLogin); draftStartAtLogin = null; }
            pendingSave = false; feedback.Text = "Saved automatically"; return true;
        }
        catch (Exception ex) { feedback.Text = ex.Message; return false; }
    }
    private void RefreshWorkspaceStatus()
    {
        status.Text = controller.Automatic ? "Bento is active" : "Bento is paused";
        count.Text = $"{controller.ManagedCount} arranged · {controller.MinimizedCount} minimized";
        string caption = controller.Automatic ? "Pause" : "Resume";
        if (pause is not null && AutomationProperties.GetName(pause) != caption)
        {
            pause.Content = Symbols.Caption(caption, caption);
            AutomationProperties.SetName(pause, caption);
        }
    }
    private void Workspace()
    {
        status = new(); count = new();
        Heading("Your workspace", "A little structure. More room to focus.");
        var hero = Card(); status.Text = controller.Automatic ? "Bento is active" : "Bento is paused"; status.FontSize = 18; status.FontWeight = FontWeights.SemiBold;
        count.Text = $"{controller.ManagedCount} arranged · {controller.MinimizedCount} minimized"; count.SetResourceReference(TextBlock.ForegroundProperty, "Secondary"); count.Margin = new Thickness(0, 4, 0, 16);
        var intro = new StackPanel { Margin = new Thickness(2, 16, 2, 15) }; intro.Children.Add(status); intro.Children.Add(count);
        var actions = new StackPanel { Orientation = Orientation.Horizontal };
        var arrange = new Button { Content = Symbols.Caption("Arrange windows", "Workspace"), Style = (Style)FindResource("Primary"), Margin = new Thickness(0, 0, 8, 0) };
        AutomationProperties.SetName(arrange, "Arrange windows");
        arrange.Click += (_, _) => { controller.AutoArrangeAll(); feedback.Text = controller.Status; };
        pause = new Button { Content = Symbols.Caption(controller.Automatic ? "Pause" : "Resume", controller.Automatic ? "Pause" : "Resume") };
        AutomationProperties.SetName(pause, controller.Automatic ? "Pause" : "Resume");
        pause.Click += (_, _) => { controller.ToggleBento(); RefreshWorkspaceStatus(); };
        actions.Children.Add(arrange); actions.Children.Add(pause); intro.Children.Add(actions); hero.Children.Add(intro);
        var layout = Card("Layout");
        Row(layout, "Space between windows", "Physical pixels", Range(draft.Gap, 4, 32, 2, " px", n => draft = draft with { Gap = n }));
        Row(layout, "Desktop margin", "Keep a little room around the edges", Range(draft.Margin, 0, 64, 2, " px", n => draft = draft with { Margin = n }));
        Row(layout, "Background darkness", "Behind windows and grabbers · clear to black", Range(draft.BackgroundDarkness, 0, 100, 5, "%", n => draft = draft with { BackgroundDarkness = n }));
        Row(layout, "Minimize windows that do not fit", "Reopen from the taskbar to give a window priority. Restored when Bento turns off.", Toggle(draft.MinimizeOverflow, v => draft = draft with { MinimizeOverflow = v }));
        var appearance = new ComboBox { ItemsSource = new[] { "System", "Light", "Dark" }, SelectedItem = draft.Theme };
        appearance.SelectionChanged += (_, _) => { draft = draft with { Theme = (string)appearance.SelectedItem }; Dirty(); };
        Row(layout, "Appearance", "Follow Windows or choose your own", appearance);
        var startup = Card("Startup");
        try
        {
            Row(startup, "Start at login", "Open Bento in the tray when you sign in.\nUses this installation folder; no administrator access needed.", Toggle(draftStartAtLogin ?? LoginStartup.IsEnabled, enabled => draftStartAtLogin = enabled));
        }
        catch (Exception ex) { startup.Children.Add(Label($"Could not read Start at login: {ex.Message}", true)); }
        var restore = new Button { Content = Symbols.Caption("Restore original window positions", "Restore"), HorizontalAlignment = HorizontalAlignment.Left };
        AutomationProperties.SetName(restore, "Restore original window positions");
        restore.Click += (_, _) => { controller.RestoreAll(); feedback.Text = controller.Status; SelectPage(page); }; content.Children.Add(restore);
    }
    private void Gestures()
    {
        Heading("Make it feel right", "Drag to swap. Hold at an edge to split.");
        var guide = Card();
        var illustration = new Grid { Height = 80, Margin = new Thickness(0, 14, 0, 14) };
        illustration.ColumnDefinitions.Add(new()); illustration.ColumnDefinitions.Add(new() { Width = new GridLength(42) }); illustration.ColumnDefinitions.Add(new());
        var left = new Border { CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(1), Padding = new Thickness(12), Child = Label("Quick drop\nSwap places") }; left.SetResourceReference(Border.BorderBrushProperty, "Line");
        var arrow = Symbols.Create("Arrow", 22); Grid.SetColumn(arrow, 1);
        var right = new Border { CornerRadius = new CornerRadius(8), Padding = new Thickness(12), Child = Label("Hold near an edge\nSplit the space") }; right.SetResourceReference(Border.BackgroundProperty, "Selection"); Grid.SetColumn(right, 2);
        illustration.Children.Add(left); illustration.Children.Add(arrow); illustration.Children.Add(right); guide.Children.Add(illustration);
        var gestures = Card("Dragging");
        Row(gestures, "Hold to split", "Wait at an edge until the slot divides.\n0 ms splits immediately.", Range(draft.SplitHoldMs, 0, 2000, 50, " ms", n => draft = draft with { SplitHoldMs = n }));
        Row(gestures, "Smooth transitions", "Respects Windows reduced-motion settings", Toggle(draft.Animate, v => draft = draft with { Animate = v }));
        Row(gestures, "Transition duration", "Short and quiet", Range(draft.AnimationMs, 80, 400, 20, " ms", n => draft = draft with { AnimationMs = n }));
        var windows = Card("Windows integration");
        Row(windows, "Let Bento handle edge snapping", "Temporarily disables Windows Snap for all apps.\nRestored when Bento pauses or exits.", Toggle(draft.SuppressWindowsSnap, v => draft = draft with { SuppressWindowsSnap = v }));
        var hotkey = new TextBox { Text = draft.Shortcut, IsReadOnly = true, IsEnabled = draft.ShortcutEnabled, Width = 140, ToolTip = "Click, then press a modifier plus a letter or number." };
        AutomationProperties.SetName(hotkey, "Shortcut keys");
        hotkey.PreviewKeyDown += (_, e) =>
        {
            if (e.Key is Key.Tab or Key.Escape) return;
            e.Handled = true; var key = e.Key == Key.System ? e.SystemKey : e.Key; uint vk = (uint)KeyInterop.VirtualKeyFromKey(key); var m = Keyboard.Modifiers;
            if (!((vk is >= 0x30 and <= 0x39) || (vk is >= 0x41 and <= 0x5A)) || m == ModifierKeys.None) return;
            uint modifiers = ((m & ModifierKeys.Alt) != 0 ? 1u : 0) | ((m & ModifierKeys.Control) != 0 ? 2u : 0) | ((m & ModifierKeys.Shift) != 0 ? 4u : 0) | ((m & ModifierKeys.Windows) != 0 ? 8u : 0);
            draft = draft with { Key = vk, Modifiers = modifiers }; hotkey.Text = draft.Shortcut; Dirty();
        };
        var shortcutControls = new StackPanel { Orientation = Orientation.Horizontal };
        var shortcutEnabled = Toggle(draft.ShortcutEnabled, enabled => { draft = draft with { ShortcutEnabled = enabled }; hotkey.IsEnabled = enabled; });
        shortcutEnabled.Margin = new Thickness(0, 0, 10, 0);
        AutomationProperties.SetName(shortcutEnabled, "Enable toggle shortcut");
        shortcutControls.Children.Add(shortcutEnabled); shortcutControls.Children.Add(hotkey);
        Row(windows, "Toggle Bento shortcut", "Change the keys or turn the shortcut off", shortcutControls);
    }
    private void Updates()
    {
        Heading("Always getting better", $"You're running Bento {UpdateService.CurrentVersion}.");
        var updates = Card("Updates");
        var repository = new TextBox { Text = draft.UpdateRepository, Width = 210, ToolTip = "owner/Bento-Layout" };
        repository.TextChanged += (_, _) => { draft = draft with { UpdateRepository = repository.Text.Trim() }; Dirty(); };
        Row(updates, "GitHub repository", "Your release source", repository);
        Row(updates, "Check when Bento starts", "Download and install only when you choose", Toggle(draft.CheckUpdates, v => draft = draft with { CheckUpdates = v }));
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 12, 0, 15) };
        var check = new Button { Content = Symbols.Caption("Check for updates", "Updates"), Style = (Style)FindResource("Primary"), Margin = new Thickness(0, 0, 8, 0) };
        var local = new Button { Content = Symbols.Caption("Choose update file…", "Folder") }; buttons.Children.Add(check); buttons.Children.Add(local); updates.Children.Add(buttons);
        AutomationProperties.SetName(check, "Check for updates"); AutomationProperties.SetName(local, "Choose update file…");
        var result = Label("", true); result.Margin = new Thickness(0, 0, 0, 12); updates.Children.Add(result);
        var browser = new Button { Content = Symbols.Caption("View releases on GitHub", "Link"), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 12) };
        AutomationProperties.SetName(browser, "View releases on GitHub");
        browser.Click += (_, _) =>
        {
            try { string repo = UpdateService.NormalizeRepository(repository.Text); System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo($"https://github.com/{repo}/releases") { UseShellExecute = true }); }
            catch (Exception ex) { result.Text = ex.Message; }
        };
        updates.Children.Add(browser);
        check.Click += async (_, _) =>
        {
            if (busy || !Save()) return;
            busy = true; check.IsEnabled = false; result.Text = "Checking GitHub…";
            try
            {
                var update = await new UpdateService().CheckAsync(draft.UpdateRepository, lifetime.Token);
                if (update is null) result.Text = "You're up to date.";
                else
                {
                    result.Text = $"Bento {update.Version} is available.\n\n{update.Notes}";
                    var install = new Button { Content = Symbols.Caption($"Download {update.Version}", "Download"), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 12) };
                    AutomationProperties.SetName(install, $"Download {update.Version}");
                    install.Click += async (_, _) =>
                    {
                        if (busy) return; busy = true; install.IsEnabled = false; result.Text = "Downloading and verifying…";
                        try { string path = await new UpdateService().DownloadAsync(update, lifetime.Token); PrepareInstall(path, result, updates); }
                        catch (Exception ex) { result.Text = ex.Message; }
                        finally { busy = false; install.IsEnabled = true; }
                    };
                    updates.Children.Add(install);
                }
            }
            catch (OperationCanceledException) { result.Text = "Update check cancelled."; }
            catch (Exception ex) { result.Text = ex.Message; }
            finally { busy = false; check.IsEnabled = true; }
        };
        local.Click += (_, _) =>
        {
            if (busy) return;
            var dialog = new OpenFileDialog { Filter = "Bento update (*.zip)|*.zip", Title = "Choose a Bento update" };
            if (dialog.ShowDialog(this) == true) PrepareInstall(dialog.FileName, result, updates);
        };
        PageLink("What's New", "What's New", "What's New");
    }
    private void PageLink(string title, string symbol, string destination)
    {
        var button = new Button { Content = Symbols.Caption(title, symbol), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 18) };
        AutomationProperties.SetName(button, title); button.Click += (_, _) => SelectPage(destination); content.Children.Add(button);
    }
    private void ReleaseCard(ReleaseNote release)
    {
        var card = Card($"{release.Version}  ·  {release.Date}");
        card.Children.Add(new TextBlock { Text = release.Title, FontSize = 16, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 13, 0, 10) });
        foreach (string change in release.Changes) { var item = Label("•  " + change, true); item.Margin = new Thickness(0, 0, 0, 12); card.Children.Add(item); }
    }
    private void WhatsNew()
    {
        Heading("What's New", "The latest improvements to Bento.");
        ReleaseCard(UpdateService.Releases[0]);
        PageLink("Update Log", "Update Log", "Update Log");
    }
    private void UpdateLog()
    {
        PageLink("Back to What's New", "Back", "What's New");
        Heading("Update Log", "Previous releases and installation history.");
        foreach (var release in UpdateService.Releases.Skip(1)) ReleaseCard(release);
        string history = Path.Combine(BentoSettings.DataDirectory, "update-history.jsonl");
        if (File.Exists(history))
        {
            var card = Card("Installation history");
            foreach (string line in File.ReadLines(history).TakeLast(10).Reverse())
                try
                {
                    using var entry = JsonDocument.Parse(line); var r = entry.RootElement;
                    var item = Label($"{r.GetProperty("Version").GetString()} · {(r.GetProperty("Success").GetBoolean() ? "Installed" : "Not installed")}\n{r.GetProperty("Message").GetString()}", true); item.Margin = new Thickness(0, 10, 0, 10); card.Children.Add(item);
                }
                catch (JsonException) { }
        }
    }
    private void PrepareInstall(string package, TextBlock result, StackPanel parent)
    {
        try
        {
            var staged = UpdateService.Stage(package);
            result.Text = $"Bento {staged.Manifest.Version} is verified and ready. Your settings will be kept. Bento will restart.";
            var restart = new Button { Content = Symbols.Caption("Install and restart", "Updates"), Style = (Style)FindResource("Primary"), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 12) };
            AutomationProperties.SetName(restart, "Install and restart");
            restart.Click += (_, _) => { try { UpdateService.Install(staged.Directory, staged.Manifest); } catch (Exception ex) { result.Text = ex.Message; } }; parent.Children.Add(restart);
        }
        catch (Exception ex) { result.Text = ex.Message; }
    }
}
