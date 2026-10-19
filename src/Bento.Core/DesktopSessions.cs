namespace Bento.Core;

public sealed class DesktopSessions<T> where T : class
{
    private readonly Dictionary<Guid, T> states = new();
    private readonly Func<T> create;
    public Guid? Desktop { get; private set; }
    public T Current { get; private set; }
    public long Revision { get; private set; }
    public IEnumerable<T> All => states.Values;
    public DesktopSessions(Func<T> create) { this.create = create; Current = create(); }
    public bool Switch(Guid desktop)
    {
        if (desktop == Guid.Empty) throw new ArgumentException("A real desktop identity is required.");
        if (Desktop == desktop) return false;
        if (!states.TryGetValue(desktop, out var state)) states[desktop] = state = create();
        Desktop = desktop; Current = state; Revision++; return true;
    }
    public void Invalidate() => Revision++;
    public void Clear() { states.Clear(); Current = create(); Desktop = null; Revision++; }
}
