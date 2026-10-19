namespace Bento.Core;

public sealed record PreviewSlot(long WindowId, string MonitorId, PixelRect Bounds);

public static class LayoutPreview
{
    // Show every projected slot on the destination display, plus changed source slots.
    // The before map spans displays so moving between monitors includes source reflow.
    public static IReadOnlyList<PreviewSlot> ForDrag(IEnumerable<PreviewSlot> before, IEnumerable<PreviewSlot> after, long movingWindow)
    {
        var original = before.ToDictionary(slot => slot.WindowId);
        var projected = after.ToArray();
        string? destination = projected.FirstOrDefault(slot => slot.WindowId == movingWindow)?.MonitorId;
        return projected.Where(slot => slot.MonitorId == destination || !original.TryGetValue(slot.WindowId, out var previous) || previous != slot)
            .OrderByDescending(slot => slot.WindowId == movingWindow).ToArray();
    }
}
