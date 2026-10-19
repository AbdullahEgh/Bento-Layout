namespace Bento.Windows;

/// <summary>Owns one global hotkey, including suspension during keyboard recording.</summary>
public sealed class ShortcutRegistration(nint handle, int id) : IDisposable
{
    private bool enabled, suspended, registered;
    private uint modifiers, key;
    public bool IsRegistered => registered;
    public bool IsSuspended => suspended;

    public void Suspend()
    {
        suspended = true;
        Release();
    }
    public bool Resume()
    {
        suspended = false;
        return EnsureRegistered();
    }
    public bool Configure(bool nextEnabled, uint nextModifiers, uint nextKey)
    {
        if (enabled == nextEnabled && modifiers == nextModifiers && key == nextKey) return EnsureRegistered();
        Release();
        if (nextEnabled && !suspended && !DesktopIntegration.RegisterShortcut(handle, id, nextModifiers, nextKey))
        {
            EnsureRegistered(); // Keep the previous binding when the replacement is unavailable.
            return false;
        }
        enabled = nextEnabled; modifiers = nextModifiers; key = nextKey;
        registered = enabled && !suspended;
        return true;
    }
    private bool EnsureRegistered()
    {
        if (!enabled || suspended || registered) return true;
        return registered = DesktopIntegration.RegisterShortcut(handle, id, modifiers, key);
    }
    private void Release()
    {
        if (registered) DesktopIntegration.UnregisterShortcut(handle, id);
        registered = false;
    }
    public void Dispose() { Release(); enabled = false; }
}
