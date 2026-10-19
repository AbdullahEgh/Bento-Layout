using System.Threading.Tasks;

namespace Bento.UI;

public sealed partial class BentoController
{
    private readonly List<OrganizingWindow> organizingWindows = new();
    private bool organizing;
    public bool Organizing => organizing;
    public void ArrangeDesktop()
    {
        if (organizing || disposed || !EnsureDesktop() || activeNativeDrag != 0) return;
        // Native fixture callers retain the synchronous contract. Ordinary Resume
        // never enters this path and never covers the desktop.
        if (windowSource is not null) { ArrangeDesktopCore(); return; }
        _ = OrganizeAsync();
    }
    private async Task OrganizeAsync()
    {
        organizing = true;
        var owner = session;
        try
        {
            foreach (var handle in dividers) handle.Hide();
            foreach (var monitor in WindowCatalog.Monitors())
            {
                var cover = new OrganizingWindow(monitor); organizingWindows.Add(cover);
                cover.Opacity = 0; cover.Show(); cover.Fade(true);
            }
            await Task.Delay(240);
            if (disposed || !EnsureDesktop() || !ReferenceEquals(owner, session)) return;
            ArrangeDesktopCore();
            // Keep bounded native settling concealed, including grid-sized clients.
            await Task.Delay(300);
        }
        catch (Exception ex) { Status = ex.Message; }
        finally
        {
            foreach (var cover in organizingWindows) cover.Fade(false);
            await Task.Delay(230);
            CloseOrganizing(); organizing = false;
            if (!disposed) { RefreshDesktopDividers(); RefreshWaiting(); }
        }
    }
    private void CloseOrganizing()
    {
        foreach (var cover in organizingWindows) cover.Close();
        organizingWindows.Clear();
    }
}
