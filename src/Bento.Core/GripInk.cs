namespace Bento.Core;

public sealed record GripSegment(double Start, double End, bool Local);
public static class GripInk
{
    // Full seam ink is 45%; local pills stay 100%. Leave an eight-DIP break at
    // either end of each pill. Input targets are computed separately.
    public static IReadOnlyList<GripSegment> Segments(double span, IEnumerable<double> localCenters)
    {
        double end = span - 4;
        if (end <= 4) return [];
        var pills = localCenters.Order().Select(center => new GripSegment(Math.Max(4, center - 40), Math.Min(end, center + 40), true))
            .Where(p => p.Start < p.End).ToArray();
        var result = new List<GripSegment>(); double cursor = 4;
        foreach (var pill in pills)
        {
            double stop = Math.Max(4, pill.Start - 8);
            if (cursor < stop) result.Add(new(cursor, stop, false));
            cursor = Math.Max(cursor, Math.Min(end, pill.End + 8));
        }
        if (cursor < end) result.Add(new(cursor, end, false));
        result.AddRange(pills);
        return result;
    }
}
