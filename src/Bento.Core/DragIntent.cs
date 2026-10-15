namespace Bento.Core;

public readonly record struct DropIntent(Placement Placement, double Progress, bool Armed);

// A monotonic clock is supplied by the host. This interaction policy is shared by future platforms.
public sealed class DragIntent
{
    private string? monitor;
    private Guid? target;
    private Placement edge = Placement.Center;
    private long enteredAt;
    private bool armed;

    public void Reset() { monitor = null; target = null; edge = Placement.Center; enteredAt = 0; armed = false; }

    public DropIntent Update(string monitorId, Guid targetId, PixelRect bounds, PixelPoint point, long now, int holdMs, double scale = 1)
    {
        var next = PlacementZones.HitTest(bounds, point);
        bool sameTarget = monitor == monitorId && target == targetId;
        // Small hand movements around an edge-zone boundary must not restart the hold timer.
        if (sameTarget && edge != Placement.Center && next != edge && WithinEdge(bounds, point, edge, 10 * scale)) next = edge;
        if (!sameTarget || next != edge)
        {
            monitor = monitorId; target = targetId; edge = next; enteredAt = now; armed = false;
        }
        if (edge == Placement.Center) return new(Placement.Center, 0, false);
        double progress = holdMs <= 0 ? 1 : Math.Clamp((now - enteredAt) / (double)holdMs, 0, 1);
        armed |= progress >= 1;
        return new(armed ? edge : Placement.Center, progress, armed);
    }

    private static bool WithinEdge(PixelRect r, PixelPoint p, Placement edge, double slack) => edge switch
    {
        Placement.Left => p.X - r.X <= r.Width * .25 + slack && p.Y >= r.Y + r.Height * .2 && p.Y <= r.Bottom - r.Height * .2,
        Placement.Right => r.Right - p.X <= r.Width * .25 + slack && p.Y >= r.Y + r.Height * .2 && p.Y <= r.Bottom - r.Height * .2,
        Placement.Top => p.Y - r.Y <= r.Height * .25 + slack && p.X >= r.X + r.Width * .2 && p.X <= r.Right - r.Width * .2,
        Placement.Bottom => r.Bottom - p.Y <= r.Height * .25 + slack && p.X >= r.X + r.Width * .2 && p.X <= r.Right - r.Width * .2,
        _ => false
    };
}
