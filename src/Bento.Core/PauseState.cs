namespace Bento.Core;

public sealed class PauseState
{
    private HashSet<long> members = new();
    private long baselineFocus;
    public bool Paused { get; private set; }
    public long? Revealed { get; private set; }
    public IReadOnlySet<long> Members => members;
    public void Enter(IEnumerable<long> windows, long focused)
    { members = windows.ToHashSet(); baselineFocus = focused; Revealed = null; Paused = true; }
    public void Focus(long window, bool clicked = false)
    {
        if (!Paused || !clicked && window == baselineFocus) return;
        baselineFocus = window;
        Revealed = members.Contains(window) ? window : null;
    }
    public bool Dimmed(long window) => Paused && members.Contains(window) && Revealed != window;
    public void Retain(IReadOnlySet<long> live)
    { members.IntersectWith(live); if (Revealed is { } id && !members.Contains(id)) Revealed = null; }
    public void Exit() { Paused = false; members.Clear(); Revealed = null; baselineFocus = 0; }
}

public sealed class StatusPress
{
    private long? began;
    private bool consumed;
    public bool Tracking => began.HasValue;
    public void Begin(long now) { began = now; consumed = false; }
    public bool Hold(long now)
    { if (began is not { } start || consumed || now - start < 550) return false; consumed = true; return true; }
    public bool End() { bool click = began.HasValue && !consumed; Cancel(); return click; }
    public void Cancel() { began = null; consumed = false; }
}

public sealed record BitLeaseRecord(uint Mask, uint Original, uint Applied);
public sealed class OwnedBitLease : IDisposable
{
    private readonly uint mask;
    private readonly Func<uint> read;
    private readonly Action<uint> write;
    private readonly Action<BitLeaseRecord?> persist;
    private BitLeaseRecord? owned;
    private bool requested;
    public bool Superseded => requested && (read() & mask) != mask;
    public OwnedBitLease(uint mask, Func<uint> read, Action<uint> write, Action<BitLeaseRecord?> persist, BitLeaseRecord? recover = null)
    {
        if (mask == 0 || recover is not null && (recover.Mask != mask || recover.Applied != mask || (recover.Original & ~mask) != 0)) throw new ArgumentException("Invalid preference lease.");
        this.mask = mask; this.read = read; this.write = write; this.persist = persist;
        owned = recover;
        Release();
    }
    public void Set(bool enabled)
    {
        if (!enabled) { requested = false; Release(); return; }
        if (requested) return; // An unchanged request must not overwrite manual OS changes.
        uint current = read();
        if ((current & mask) == mask) { requested = true; return; } // User already owns this preference.
        var next = new BitLeaseRecord(mask, current & mask, mask);
        persist(next); owned = next; requested = true; // Journal must be durable before the OS write.
        try
        {
            write(current | mask);
            if ((read() & mask) != mask) throw new InvalidOperationException("The system did not accept this preference.");
        }
        catch { requested = false; try { Release(); } catch { /* Keep journal for recovery. */ } throw; }
    }
    private void Release()
    {
        if (owned is not { } entry) return;
        uint current = read();
        if ((current & mask) == entry.Applied)
        {
            uint restored = (current & ~mask) | entry.Original;
            write(restored);
            if ((read() & mask) != entry.Original) throw new InvalidOperationException("The original system preference could not be restored.");
        }
        persist(null); owned = null;
    }
    public void Dispose() { requested = false; Release(); }
}
