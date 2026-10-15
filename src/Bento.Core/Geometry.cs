namespace Bento.Core;

// All engine coordinates are physical desktop pixels, including negative monitor origins.
public readonly record struct PixelPoint(int X, int Y);
public readonly record struct PixelSize(int Width, int Height);
public readonly record struct PixelRect(int X, int Y, int Width, int Height)
{
    public int Right => X + Width;
    public int Bottom => Y + Height;
    public bool Contains(PixelPoint p) => p.X >= X && p.X < Right && p.Y >= Y && p.Y < Bottom;
    public PixelRect Inset(int amount) => new(X + amount, Y + amount,
        Math.Max(0, Width - amount * 2), Math.Max(0, Height - amount * 2));
}

public enum SplitAxis { Horizontal, Vertical }
public enum Placement { Left, Right, Top, Bottom, Center }

public static class PlacementZones
{
    public static Placement HitTest(PixelRect rect, PixelPoint point)
    {
        if (!rect.Contains(point)) throw new ArgumentOutOfRangeException(nameof(point));
        double x = (point.X - rect.X) / (double)rect.Width;
        double y = (point.Y - rect.Y) / (double)rect.Height;
        if (x >= .25 && x <= .75 && y >= .25 && y <= .75) return Placement.Center;
        double nearest = Math.Min(Math.Min(x, 1 - x), Math.Min(y, 1 - y));
        if (nearest == x) return Placement.Left;
        if (nearest == 1 - x) return Placement.Right;
        return nearest == y ? Placement.Top : Placement.Bottom;
    }
}
