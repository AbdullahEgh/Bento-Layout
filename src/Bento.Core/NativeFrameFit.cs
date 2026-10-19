namespace Bento.Core;

public static class NativeFrameFit
{
    public static bool Accepts(PixelRect actual, PixelRect slot) => Math.Abs(actual.X - slot.X) <= 2 && Math.Abs(actual.Y - slot.Y) <= 2 &&
        actual.Width > 0 && actual.Height > 0 && slot.Width - actual.Width is >= -2 and <= 32 && slot.Height - actual.Height is >= -2 and <= 32;
    // Cell slack belongs to an already-applied allocation. A newly requested
    // allocation (including a small Undo/Redo) must still issue a native move.
    public static bool NeedsPlacement(PixelRect actual, PixelRect slot, PixelRect? applied) => applied != slot || !Accepts(actual, slot);
    public static PixelRect InwardTarget(PixelRect actual, PixelRect slot)
    {
        int dx = actual.Width - slot.Width, dy = actual.Height - slot.Height;
        return slot with { Width = dx is >= 3 and <= 32 ? Math.Max(1, slot.Width - dx - 1) : slot.Width,
            Height = dy is >= 3 and <= 32 ? Math.Max(1, slot.Height - dy - 1) : slot.Height };
    }
}

// A refused width says nothing about the other dimension. Origin failures are
// never minimum evidence, and a subsequently accepted smaller frame clears a hint.
public sealed class NativeMinimumTracker
{
    private sealed record Entry(uint Process, PixelSize Reported, int? Width, int? Height);
    private readonly Dictionary<long, Entry> entries = new();
    public PixelSize Effective(long window, uint process, PixelSize reported)
    {
        if (!entries.TryGetValue(window, out var e) || e.Process != process) e = new(process, reported, null, null);
        else if (e.Reported != reported) e = e with { Reported = reported,
            Width = e.Reported.Width == reported.Width ? e.Width : null, Height = e.Reported.Height == reported.Height ? e.Height : null };
        entries[window] = e;
        return new(Math.Max(reported.Width, e.Width ?? 0), Math.Max(reported.Height, e.Height ?? 0));
    }
    public void Observe(long window, uint process, PixelSize reported, PixelRect actual, PixelRect target, bool learn)
    {
        Effective(window, process, reported);
        var e = entries[window];
        int? width = e.Width is { } w && actual.Width < w ? null : e.Width;
        int? height = e.Height is { } h && actual.Height < h ? null : e.Height;
        if (learn && Math.Abs(actual.X - target.X) <= 2 && Math.Abs(actual.Y - target.Y) <= 2 && !NativeFrameFit.Accepts(actual, target))
        {
            if (actual.Width > target.Width + 2) width = Math.Max(width ?? reported.Width, actual.Width);
            if (actual.Height > target.Height + 2) height = Math.Max(height ?? reported.Height, actual.Height);
        }
        entries[window] = e with { Width = width, Height = height };
    }
    public void Forget(long window) => entries.Remove(window);
    public void Retain(IReadOnlySet<long> windows)
    { foreach (long id in entries.Keys.Where(id => !windows.Contains(id)).ToArray()) entries.Remove(id); }
}

public static class NativeSeamAlignment
{
    public static long Score(LayoutNode root, PixelRect area, int gap, IReadOnlyDictionary<long, PixelRect> frames)
    {
        try
        {
            long total = 0;
            foreach (var region in LayoutEngine.Calculate(root, area, gap).Regions)
            {
                if (!frames.TryGetValue(region.Window.WindowId, out var actual) || !NativeFrameFit.Accepts(actual, region.Bounds)) return long.MaxValue;
                total += Math.Max(0, region.Bounds.Width - actual.Width) + Math.Max(0, region.Bounds.Height - actual.Height);
            }
            return total;
        }
        catch (LayoutConstraintException) { return long.MaxValue; }
    }
    public static LayoutNode? Propose(LayoutNode root, PixelRect area, int gap, IReadOnlyDictionary<long, PixelRect> frames)
    {
        if (Score(root, area, gap, frames) == long.MaxValue) return null;
        var layout = LayoutEngine.Calculate(root, area, gap);
        LayoutNode? best = null; int bestSlack = 0;
        void Visit(LayoutNode node)
        {
            if (node is not SplitNode s) return;
            var divider = layout.Dividers.Single(d => d.SplitId == s.Id);
            bool h = s.Axis == SplitAxis.Horizontal;
            foreach (var (child, first) in new[] { (s.First, true), (s.Second, false) })
            {
                if (child is not WindowNode w || !frames.TryGetValue(w.WindowId, out var actual)) continue;
                var slot = layout.Regions.Single(r => r.Window.WindowId == w.WindowId).Bounds;
                int slack = h ? slot.Width - actual.Width : slot.Height - actual.Height;
                if (slack is < 3 or > 32 || slack <= bestSlack) continue;
                int length = (h ? divider.ParentBounds.Width : divider.ParentBounds.Height) - gap;
                int offset = h ? divider.Bounds.X - divider.ParentBounds.X : divider.Bounds.Y - divider.ParentBounds.Y;
                if (length <= 0) continue;
                var candidate = LayoutEngine.Resize(root, s.Id, (offset + (first ? -slack : slack)) / (double)length);
                var proposed = LayoutEngine.Calculate(candidate, area, gap).Regions.Single(r => r.Window.WindowId == w.WindowId).Bounds;
                if ((h ? proposed.Width == actual.Width : proposed.Height == actual.Height)) { bestSlack = slack; best = candidate; }
            }
            Visit(s.First); Visit(s.Second);
        }
        Visit(root); return best;
    }
}
