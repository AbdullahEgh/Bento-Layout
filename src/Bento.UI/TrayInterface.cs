using Forms = System.Windows.Forms;
using Drawing = System.Drawing;

namespace Bento.UI;

internal sealed class TrayInterface : IDisposable
{
    public Forms.NotifyIcon Icon { get; }
    private readonly BentoController controller;
    private readonly Forms.ContextMenuStrip menu = new();
    private readonly Forms.ToolStripMenuItem pause, toggle, taskbar, undo;
    private readonly Forms.Timer pressTimer = new() { Interval = 50 };
    private readonly StatusPress press = new();
    private readonly List<Drawing.Image> menuImages = new();
    private Drawing.Icon? image;
    private bool disposed;
    private (bool Active, bool Paused, bool Suspended, bool Dark, bool TaskbarDark)? appearance;

    public TrayInterface(BentoController controller, Action rememberActive, Func<long> activeWindow)
    {
        this.controller = controller;
        void Run(Action action) => Application.Current.Dispatcher.BeginInvoke(new Action(() => { if (!disposed) action(); }));
        Forms.ToolStripMenuItem Item(string text, Action action)
        {
            var item = new Forms.ToolStripMenuItem(text);
            item.Click += (_, _) => Run(action); menu.Items.Add(item); return item;
        }
        pause = Item("Pause Bento", controller.TogglePause);
        toggle = Item("Turn Bento on", controller.ToggleBento);
        taskbar = Item("Hide Taskbar", controller.ToggleTaskbar);
        menu.Items.Add(new Forms.ToolStripSeparator());
        undo = Item("Undo Layout Change", controller.Undo);
        Item("Settings…", () => controller.ShowInterface());
        menu.Items.Add(new Forms.ToolStripSeparator());
        Item("Quit Bento", controller.QuitKeepingWindows);
        menu.Opening += (_, _) => { press.Cancel(); pressTimer.Stop(); controller.CheckDesktopContext(); rememberActive(); Refresh(); };
        Icon = new Forms.NotifyIcon { ContextMenuStrip = menu, Visible = true };
        Icon.MouseDown += (_, e) =>
        {
            if (disposed) return;
            if (e.Button != Forms.MouseButtons.Left) { press.Cancel(); pressTimer.Stop(); return; }
            Run(controller.CheckDesktopContext); press.Begin(Environment.TickCount64); pressTimer.Start();
        };
        Icon.MouseUp += (_, e) =>
        {
            if (disposed) return;
            if (e.Button != Forms.MouseButtons.Left) return;
            pressTimer.Stop(); if (press.End()) Run(controller.TrayClick);
        };
        pressTimer.Tick += (_, _) =>
        {
            if (disposed) return;
            if (WindowCatalog.EscapeDown || !WindowCatalog.LeftButtonDown) { press.Cancel(); pressTimer.Stop(); return; }
            if (controller.Automatic && press.Hold(Environment.TickCount64)) Run(controller.TrayHold);
        };
        Refresh();
    }
    public void Refresh()
    {
        if (disposed) return;
        bool active = controller.Automatic, paused = controller.Paused, dark = AppTheme.SystemDark;
        bool taskbarDark = Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme", 0) is int light && light == 0;
        pause.Text = paused ? "Resume Bento" : "Pause Bento"; pause.Checked = paused;
        toggle.Text = active ? "Turn Bento off" : "Turn Bento on"; toggle.Checked = active;
        taskbar.Checked = controller.HideTaskbar; taskbar.Enabled = active && !controller.Suspended;
        pause.Enabled = toggle.Enabled = !controller.Suspended;
        undo.Enabled = active && !paused && !controller.Suspended;
        Icon.Text = controller.Suspended ? "Bento waiting for desktop · Right-click for settings" : paused ? "Bento paused · Click to resume · Hold to hide taskbar" : active ? "Bento active · Click to turn off · Hold to hide taskbar" : "Bento off · Click to arrange windows";
        var next = (active, paused, controller.Suspended, dark, taskbarDark);
        if (appearance == next) return;
        appearance = next;
        var old = image; image = AppIcons.CreateTrayIcon(active && !controller.Suspended, taskbarDark, paused && !controller.Suspended); Icon.Icon = image; old?.Dispose();
        menu.Renderer = new MenuRenderer(dark);
        menu.BackColor = dark ? Drawing.Color.FromArgb(32, 34, 38) : Drawing.Color.FromArgb(250, 250, 250);
        menu.ForeColor = dark ? Drawing.Color.FromArgb(240, 242, 245) : Drawing.Color.FromArgb(30, 32, 36);
        foreach (var previous in menuImages) previous.Dispose(); menuImages.Clear();
        int glyph = 0;
        foreach (Forms.ToolStripItem item in menu.Items)
        {
            item.BackColor = menu.BackColor; item.ForeColor = menu.ForeColor;
            if (item is not Forms.ToolStripMenuItem) continue;
            var icon = MenuGlyph(glyph++, menu.ForeColor, paused); menuImages.Add(icon); item.Image = icon;
        }
    }
    private static Drawing.Bitmap MenuGlyph(int kind, Drawing.Color color, bool paused)
    {
        var bitmap = new Drawing.Bitmap(16, 16);
        using var graphics = Drawing.Graphics.FromImage(bitmap);
        graphics.SmoothingMode = Drawing.Drawing2D.SmoothingMode.AntiAlias;
        using var pen = new Drawing.Pen(color, 1.5f); using var brush = new Drawing.SolidBrush(color);
        switch (kind)
        {
            case 0:
                if (paused) graphics.FillPolygon(brush, new[] { new Drawing.Point(5, 3), new Drawing.Point(13, 8), new Drawing.Point(5, 13) });
                else { graphics.FillRectangle(brush, 4, 3, 3, 10); graphics.FillRectangle(brush, 10, 3, 3, 10); }
                break;
            case 1: graphics.DrawArc(pen, 2, 2, 12, 12, -45, 270); graphics.DrawLine(pen, 8, 1, 8, 8); break;
            case 2: graphics.DrawRectangle(pen, 2, 3, 12, 10); graphics.DrawLine(pen, 3, 10, 13, 10); break;
            case 3: graphics.DrawArc(pen, 4, 4, 9, 8, 180, 230); graphics.DrawLine(pen, 4, 7, 4, 3); graphics.DrawLine(pen, 4, 7, 8, 7); break;
            case 4: graphics.DrawEllipse(pen, 3, 3, 10, 10); graphics.DrawEllipse(pen, 6, 6, 4, 4); break;
            default: graphics.DrawLine(pen, 4, 4, 12, 12); graphics.DrawLine(pen, 4, 12, 12, 4); break;
        }
        return bitmap;
    }
    public void Dispose()
    {
        if (disposed) return; disposed = true;
        press.Cancel(); pressTimer.Stop(); pressTimer.Dispose(); Icon.Visible = false; Icon.Dispose(); menu.Dispose(); image?.Dispose();
        foreach (var icon in menuImages) icon.Dispose(); menuImages.Clear();
    }

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
