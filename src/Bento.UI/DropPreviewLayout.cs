using System.Windows.Interop;

namespace Bento.UI;

// Pools slot panels by application identity, with one shared dimmer per display.
internal sealed class DropPreviewLayout
{
    private readonly Dictionary<long, DropPreviewWindow> panels = new();
    private readonly Dictionary<string, PreviewDimWindow> dimmers = new();

    public void Present(IReadOnlyList<PreviewSlot> slots, IReadOnlyList<DesktopMonitor> monitors, long destination, bool animate, bool conflict = false)
    {
        var ids = slots.Select(slot => slot.WindowId).ToHashSet();
        foreach (var pair in panels.Where(pair => !ids.Contains(pair.Key))) pair.Value.Hide();
        var displays = slots.Select(slot => slot.MonitorId).ToHashSet();
        foreach (var pair in dimmers.Where(pair => !displays.Contains(pair.Key))) pair.Value.Hide();
        foreach (var monitor in monitors.Where(m => displays.Contains(m.Id)))
        {
            if (!dimmers.TryGetValue(monitor.Id, out var dimmer)) dimmers[monitor.Id] = dimmer = new();
            bool raisedDimmer = dimmer.Present(monitor.Bounds, monitor.Scale);
            var siblings = new List<long>();
            foreach (var slot in slots.Where(slot => slot.MonitorId == monitor.Id))
            {
                if (!panels.TryGetValue(slot.WindowId, out var panel)) panels[slot.WindowId] = panel = new();
                panel.SlotWindowId = slot.WindowId;
                panel.Present(slot.Bounds, monitor.Scale, animate, destination: slot.WindowId == destination, conflict: conflict && slot.WindowId == destination);
                siblings.Add(new WindowInteropHelper(panel).Handle.ToInt64());
            }
            // A resized/reopened dimmer was raised; keep it below every slot,
            // including unchanged pooled panels whose Present call is a no-op.
            if (raisedDimmer) DesktopIntegration.PlaceBehindApplications(new WindowInteropHelper(dimmer).Handle, siblings);
            // The actual dragged app stays above its destinations. Avoid changing
            // its topmost style: helper windows are placed relative to it instead.
            if (WindowCatalog.Exists(destination) && !WindowCatalog.IsMinimized(destination))
            {
                foreach (var slot in slots.Where(slot => slot.MonitorId == monitor.Id))
                    DesktopIntegration.PlaceBelow(new WindowInteropHelper(panels[slot.WindowId]).Handle, (nint)destination);
                DesktopIntegration.PlaceBehindApplications(new WindowInteropHelper(dimmer).Handle, siblings);
            }
        }
    }
    public void Hide()
    {
        foreach (var panel in panels.Values) panel.Hide();
        foreach (var dimmer in dimmers.Values) dimmer.Hide();
    }
    public void Close()
    {
        foreach (var panel in panels.Values) panel.Close();
        foreach (var dimmer in dimmers.Values) dimmer.Close();
        panels.Clear(); dimmers.Clear();
    }
}
