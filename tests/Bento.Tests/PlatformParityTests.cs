using Bento.Core;
using static Bento.Tests.Program;

namespace Bento.Tests;

internal static class PlatformParityTests
{
    private static WindowNode W(long id) => WindowNode.Create(id, new(100, 100));
    private static SplitNode Pair(LayoutNode a, LayoutNode b, SplitAxis axis = SplitAxis.Horizontal, double ratio = .5) => new(Guid.NewGuid(), axis, ratio, a, b);
    private sealed class Session { public bool Active; public readonly List<long> Windows = new(); }
    public static void RunAll()
    {
        Run("Unchanged overflow retains the edited tree instead of rebuilding every sample", () =>
        {
            var a = WindowNode.Create(1, new(300, 300)); var b = WindowNode.Create(2, new(300, 300)); var overflow = WindowNode.Create(3, new(300, 300));
            var original = Pair(a, b, ratio: .6); var area = new PixelRect(0, 0, 808, 308); LayoutNode? root = original;
            for (int i = 0; i < 10; i++) root = AutoLayout.Fitting(new[] { overflow, a, b }, area, previous: root);
            Equal<LayoutNode?>(original, root);
        });
        Run("Cell-rounded frames accept bounded slack and reject displaced or oversized frames", () =>
        {
            var slot = new PixelRect(-1200, 30, 800, 600);
            Check(NativeFrameFit.Accepts(new(-1200, 30, 784, 588), slot));
            Check(!NativeFrameFit.Accepts(slot with { X = slot.X + 3 }, slot));
            Check(!NativeFrameFit.Accepts(slot with { Width = 803 }, slot));
            Check(!NativeFrameFit.Accepts(slot with { Height = 567 }, slot));
            Equal(slot with { Width = 791 }, NativeFrameFit.InwardTarget(slot with { Width = 808 }, slot));
            Equal(slot, NativeFrameFit.InwardTarget(slot with { Width = 900 }, slot));
        });
        Run("Minimum learning is axis-specific and a smaller accepted frame clears the hint", () =>
        {
            var hints = new NativeMinimumTracker(); var reported = new PixelSize(180, 120); var target = new PixelRect(0, 0, 500, 400);
            hints.Observe(1, 10, reported, target with { Width = 550 }, target, learn: true);
            Equal(new PixelSize(550, 120), hints.Effective(1, 10, reported));
            hints.Observe(1, 10, reported, new(0, 0, 450, 300), new(0, 0, 450, 300), learn: false);
            Equal(reported, hints.Effective(1, 10, reported));
            hints.Observe(1, 10, reported, target with { Height = 460 }, target, learn: true);
            Equal(new PixelSize(180, 460), hints.Effective(1, 10, reported));
            Equal(reported, hints.Effective(1, 11, reported));
        });
        Run("Origin failures and work-area squeeze cannot poison minimum hints", () =>
        {
            var hints = new NativeMinimumTracker(); var reported = new PixelSize(180, 120); var target = new PixelRect(0, 0, 500, 400);
            hints.Observe(1, 10, reported, target with { X = 30, Width = 600, Height = 600 }, target, learn: true);
            Equal(reported, hints.Effective(1, 10, reported));
            hints.Observe(1, 10, reported, target with { Width = 600 }, target, learn: false);
            Equal(reported, hints.Effective(1, 10, reported));
        });
        Run("Native seam proposal retains membership and requires post-move improvement", () =>
        {
            var root = Pair(W(1), W(2)); var area = new PixelRect(0, 0, 1008, 808);
            var layout = LayoutEngine.Calculate(root, area, 8);
            var frames = layout.Regions.ToDictionary(r => r.Window.WindowId, r => r.Bounds);
            frames[1] = frames[1] with { Width = frames[1].Width - 12 };
            Equal(12L, NativeSeamAlignment.Score(root, area, 8, frames));
            var proposed = NativeSeamAlignment.Propose(root, area, 8, frames)!;
            Equal(root.Id, proposed.Id);
            Check(LayoutEngine.Windows(root).Select(w => w.WindowId).SequenceEqual(LayoutEngine.Windows(proposed).Select(w => w.WindowId)));
            var accepted = LayoutEngine.Calculate(proposed, area, 8).Regions.ToDictionary(r => r.Window.WindowId, r => r.Bounds);
            Equal(0L, NativeSeamAlignment.Score(proposed, area, 8, accepted));
            frames[2] = frames[2] with { X = frames[2].X + 10 };
            Check(NativeSeamAlignment.Propose(root, area, 8, frames) is null);
        });
        Run("Pause dims the initially focused member until a real click or focus change", () =>
        {
            var pause = new PauseState(); pause.Enter(new long[] { 1, 2 }, 1);
            Check(pause.Dimmed(1) && pause.Dimmed(2));
            pause.Focus(1); Check(pause.Dimmed(1));
            pause.Focus(1, clicked: true); Check(!pause.Dimmed(1) && pause.Dimmed(2));
            pause.Focus(2); Check(pause.Dimmed(1) && !pause.Dimmed(2));
            pause.Focus(9); Check(pause.Dimmed(1) && pause.Dimmed(2));
            pause.Exit(); Check(!pause.Paused && !pause.Dimmed(1));
        });
        Run("Paused membership closes without admitting floating windows", () =>
        {
            var pause = new PauseState(); pause.Enter(new long[] { 1, 2 }, 1); pause.Focus(1, clicked: true);
            pause.Retain(new HashSet<long> { 2, 3 });
            Check(pause.Paused && pause.Revealed is null); Check(pause.Members.SetEquals(new long[] { 2 })); Check(!pause.Dimmed(3));
        });
        Run("Desktop sessions retain independent activation and membership; new desktops start off", () =>
        {
            var store = new DesktopSessions<Session>(() => new()); var a = Guid.NewGuid(); var b = Guid.NewGuid();
            store.Switch(a); store.Current.Active = true; store.Current.Windows.Add(1); long pending = store.Revision;
            store.Switch(b); Check(!store.Current.Active); Equal(0, store.Current.Windows.Count); Check(pending != store.Revision);
            store.Current.Windows.Add(2); store.Switch(a); Check(store.Current.Active); Equal(1L, store.Current.Windows.Single());
            var state = store.Current; store.Invalidate(); Check(ReferenceEquals(state, store.Current));
            bool refused = false; try { store.Switch(Guid.Empty); } catch (ArgumentException) { refused = true; } Check(refused);
        });
        Run("Destroyed HWND is forgotten from saved memory and every history branch", () =>
        {
            var history = new LayoutHistory(); var state = new WorkspaceState().WithRoot("A", Pair(W(1), W(2)));
            history.Commit(state); history.Commit(state.Remove(2)); history.Undo();
            var saved = new SessionLayoutSnapshot(state, new[] { new SessionWindow(1, 10, new(100, 100)), new SessionWindow(2, 10, new(100, 100)) });
            history.Forget(1); Check(!history.Current.Windows.Any(w => w.WindowId == 1));
            Check(!history.Redo().Windows.Any(w => w.WindowId == 1)); Check(!history.Undo().Windows.Any(w => w.WindowId == 1));
            var live = new[] { new SessionWindow(1, 10, new(100, 100)), new SessionWindow(2, 10, new(100, 100)) };
            var pruned = saved.Without(1); Check(!pruned.Contains(1)); Equal(2L, pruned.Reconcile(live, new[] { "A" }).Windows.Single().WindowId);
        });
        Run("Taskbar lease journals before write and preserves unrelated bits on release", () =>
        {
            uint state = 4; BitLeaseRecord? journal = null; var order = new List<string>();
            using (var lease = new OwnedBitLease(1, () => state, value => { order.Add("write"); state = value; }, entry => { order.Add(entry is null ? "clear" : "journal"); journal = entry; }))
            {
                lease.Set(true); Equal("journal", order[0]); Equal("write", order[1]); Equal(5u, state); Check(journal is not null);
                state |= 2;
            }
            Equal(6u, state); Check(journal is null); Equal("clear", order.Last());
        });
        Run("Manual taskbar change wins even when the initial preference already matched", () =>
        {
            uint state = 1; int writes = 0;
            using var lease = new OwnedBitLease(1, () => state, value => { writes++; state = value; }, _ => { });
            lease.Set(true); Equal(0, writes); state = 0;
            lease.Set(true); Equal(0, writes); Check(lease.Superseded);
            lease.Set(false); Equal(0u, state);
        });
        Run("Taskbar recovery restores only the owned bit and honors a newer manual value", () =>
        {
            uint state = 5; bool cleared = false;
            using (var lease = new OwnedBitLease(1, () => state, value => state = value, entry => cleared = entry is null, new(1, 0, 1)))
            { Equal(4u, state); Check(cleared); }
            state = 4; int writes = 0;
            using var manual = new OwnedBitLease(1, () => state, value => { state = value; writes++; }, _ => { }, new(1, 0, 1));
            Equal(0, writes); Equal(4u, state);
        });
        Run("Journal failure cannot change the taskbar and a failed restore retains recovery", () =>
        {
            uint state = 0; int writes = 0; bool failJournal = true;
            using var lease = new OwnedBitLease(1, () => state, value => { writes++; state = value; }, _ => { if (failJournal) throw new System.IO.IOException("fixture"); });
            try { lease.Set(true); } catch (System.IO.IOException) { }
            Equal(0, writes); Equal(0u, state); failJournal = false; lease.Set(true); Equal(1u, state);
        });
        Run("Long press fires once, consumes release and cancellation clears tracking", () =>
        {
            var press = new StatusPress(); press.Begin(100); Check(!press.Hold(649)); Check(press.Hold(650));
            Check(!press.Hold(1200)); Check(!press.End()); Check(!press.Tracking);
            press.Begin(2000); press.Cancel(); Check(!press.End()); press.Begin(3000); Check(press.End());
        });
        Run("Join cue selects only the connected new parallel group and never pulses an existing join", () =>
        {
            var root = Pair(W(1), W(2)); var area = new PixelRect(0, 0, 1008, 808);
            var local = new Divider(Guid.NewGuid(), SplitAxis.Horizontal, new(500, 0, 8, 400), new(0, 0, 1008, 400));
            var group = new ResizeHandle(new(Guid.NewGuid(), SplitAxis.Horizontal, new(500, 0, 8, 808), area), root, true);
            var unrelated = new ResizeHandle(new(Guid.NewGuid(), SplitAxis.Horizontal, new(700, 0, 8, 808), area), root, true);
            var perpendicular = new ResizeHandle(new(Guid.NewGuid(), SplitAxis.Vertical, new(0, 400, 1008, 8), area), root, true);
            var previous = new[] { new ResizeHandle(local with { Bounds = local.Bounds with { X = 490 } }, root) };
            var joined = new[] { group, unrelated, perpendicular, new ResizeHandle(local, root) };
            Equal(group, ResizeHandles.NewlyJoinedSection(joined, previous, local));
            Check(ResizeHandles.NewlyJoinedSection(joined, joined, local) is null);
            Check(ResizeHandles.NewlyJoinedSection(joined, [], local) is null);
            Equal(1d, ResizeHandles.JoinOpacity(.18)); Equal(0d, ResizeHandles.JoinOpacity(.55));
        });
        Run("Maximization and captioned coverage are not classified as borderless fullscreen", () =>
        {
            var screen = new PixelRect(-1000, 0, 1000, 800);
            Check(FullscreenGeometry.Borderless(screen, screen, false, false));
            Check(!FullscreenGeometry.Borderless(screen, screen, true, false));
            Check(!FullscreenGeometry.Borderless(screen, screen, false, true));
            Check(!FullscreenGeometry.Borderless(screen.Inset(8), screen, false, false));
        });
        Run("Fullscreen reference can restore slots while retaining newly admitted membership", () =>
        {
            var root = Pair(W(1), W(2), ratio: .6); var state = new WorkspaceState().WithRoot("A", root);
            var reference = new SessionLayoutSnapshot(state, new[] { new SessionWindow(1, 10, new(100, 100)), new SessionWindow(2, 20, new(100, 100)) });
            var projected = state.Remove(1); Equal(2L, projected.Windows.Single().WindowId);
            var live = new[] { new SessionWindow(1, 10, new(100, 100)), new SessionWindow(2, 20, new(100, 100)), new SessionWindow(3, 30, new(100, 100)) };
            var restored = reference.Reconcile(live, new[] { "A" }); Equal(.6, ((SplitNode)restored.Roots["A"]!).Ratio);
            var combined = AutoLayout.Fitting(live.Select(w => WindowNode.Create(w.Id, w.Minimum)).ToArray(), new(0, 0, 1008, 808), previous: restored.Roots["A"]);
            Equal(3, LayoutEngine.Windows(combined).Count());
        });
    }
}
