namespace Bento.Core;

public static class SlotPreview
{
    // A gesture targets the committed slot, even if removing its source later expands that slot.
    public static PixelRect Bounds(PixelRect slot, Placement placement, int gap)
    {
        int width = Math.Max(1, (slot.Width - gap) / 2);
        int height = Math.Max(1, (slot.Height - gap) / 2);
        return placement switch
        {
            Placement.Left => slot with { Width = width },
            Placement.Right => new(slot.X + width + gap, slot.Y, slot.Width - width - gap, slot.Height),
            Placement.Top => slot with { Height = height },
            Placement.Bottom => new(slot.X, slot.Y + height + gap, slot.Width, slot.Height - height - gap),
            _ => slot
        };
    }
}
