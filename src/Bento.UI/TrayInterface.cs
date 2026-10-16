using Forms = System.Windows.Forms;
using Drawing = System.Drawing;

namespace Bento.UI;

internal sealed class TrayInterface : IDisposable
{
    public Forms.NotifyIcon Icon { get; }
    private readonly BentoController controller;
    private readonly Forms.ContextMenuStrip menu = new();
    private readonly Forms.ToolStripMenuItem toggle, save, undo, redo, release;
    private Drawing.Icon? image;
    private (bool Active, bool Dark, bool TaskbarDark)? appearance;

    public TrayInterface(BentoController controller, Action rememberActive, Func<long> activeWindow)
    {
        this.controller = controller;
        void Run(Action action) => Application.Current.Dispatcher.BeginInvoke(action);
        Forms.ToolStripMenuItem Item(string text, Action action)
        {
            var item = new Forms.ToolStripMenuItem(text);
            item.Click += (_, _) => Run(action); menu.Items.Add(item); return item;
        }
        toggle = Item("Turn Bento on", controller.ToggleBento);
        save = Item("Save Bento", controller.SaveBento);
        Item("Arrange all windows", controller.AutoArrangeAll);
        menu.Items.Add(new Forms.ToolStripSeparator());
        undo = Item("Undo", controller.Undo); redo = Item("Redo", controller.Redo);
        release = Item("Release active window", () => controller.Remove(activeWindow()));
        menu.Items.Add(new Forms.ToolStripSeparator());
        Item("Settings…", () => controller.ShowInterface());
        Item("What's New", () => controller.ShowInterface("What's New"));
        Item("Updates…", () => controller.ShowInterface("Updates"));
        menu.Items.Add(new Forms.ToolStripSeparator());
        Item("Quit Bento", () => Application.Current.Shutdown());
        menu.Opening += (_, _) => { rememberActive(); Refresh(); };
        Icon = new Forms.NotifyIcon { ContextMenuStrip = menu, Visible = true };
        Icon.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) Run(controller.ToggleBento); };
        Refresh();
    }
    public void Refresh()
    {
        bool active = controller.Automatic, dark = AppTheme.SystemDark;
        bool taskbarDark = Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme", 0) is int light && light == 0;
        toggle.Text = active ? "Turn Bento off · Restore windows" : "Turn Bento on";
        toggle.Checked = active;
        save.Enabled = active && controller.ManagedCount > 0;
        undo.Enabled = redo.Enabled = release.Enabled = active;
        Icon.Text = active ? "Bento active · Click to restore windows" : "Bento inactive · Click to arrange windows";
        var next = (active, dark, taskbarDark);
        if (appearance == next) return;
        appearance = next;
        var old = image; image = AppIcons.CreateTrayIcon(active, taskbarDark); Icon.Icon = image; old?.Dispose();
        menu.Renderer = new MenuRenderer(dark);
        menu.BackColor = dark ? Drawing.Color.FromArgb(32, 34, 38) : Drawing.Color.FromArgb(250, 250, 250);
        menu.ForeColor = dark ? Drawing.Color.FromArgb(240, 242, 245) : Drawing.Color.FromArgb(30, 32, 36);
        foreach (Forms.ToolStripItem item in menu.Items) { item.BackColor = menu.BackColor; item.ForeColor = menu.ForeColor; }
    }
    public void Dispose() { Icon.Visible = false; Icon.Dispose(); menu.Dispose(); image?.Dispose(); }

    private sealed class MenuRenderer(bool dark) : Forms.ToolStripProfessionalRenderer(new MenuColors(dark))
    {
        protected override void OnRenderItemText(Forms.ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = e.Item.Enabled ? (dark ? Drawing.Color.WhiteSmoke : Drawing.Color.FromArgb(30, 32, 36))
                : (dark ? Drawing.Color.FromArgb(140, 145, 153) : Drawing.Color.Gray);
            base.OnRenderItemText(e);
        }
    }
    private sealed class MenuColors(bool dark) : Forms.ProfessionalColorTable
    {
        private Drawing.Color Surface => dark ? Drawing.Color.FromArgb(32, 34, 38) : Drawing.Color.FromArgb(250, 250, 250);
        public override Drawing.Color ToolStripDropDownBackground => Surface;
        public override Drawing.Color ImageMarginGradientBegin => Surface;
        public override Drawing.Color ImageMarginGradientMiddle => Surface;
        public override Drawing.Color ImageMarginGradientEnd => Surface;
        public override Drawing.Color MenuItemSelected => dark ? Drawing.Color.FromArgb(60, 64, 70) : Drawing.Color.FromArgb(226, 232, 237);
        public override Drawing.Color MenuItemBorder => MenuItemSelected;
        public override Drawing.Color MenuBorder => dark ? Drawing.Color.FromArgb(73, 77, 84) : Drawing.Color.FromArgb(205, 208, 212);
        public override Drawing.Color SeparatorDark => MenuBorder;
        public override Drawing.Color SeparatorLight => Surface;
        public override Drawing.Color CheckBackground => MenuItemSelected;
        public override Drawing.Color CheckSelectedBackground => MenuItemSelected;
    }
}
