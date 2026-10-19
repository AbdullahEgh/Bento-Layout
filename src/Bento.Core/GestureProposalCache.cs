namespace Bento.Core;

// A destination key alone is insufficient when another member closes or changes
// constraints during a gesture. Both successful and rejected proposals belong to
// one immutable workspace snapshot.
public sealed class GestureProposalCache<TKey, TValue> where TKey : notnull where TValue : class
{
    private object? context;
    private readonly Dictionary<TKey, TValue?> entries = new();
    public bool Use(object basis)
    {
        if (ReferenceEquals(context, basis)) return false;
        entries.Clear(); context = basis; return true;
    }
    public TValue? this[TKey key] { set => entries[key] = value; }
    public bool TryGetValue(TKey key, out TValue? value) => entries.TryGetValue(key, out value);
    public void Clear() { entries.Clear(); context = null; }
}
