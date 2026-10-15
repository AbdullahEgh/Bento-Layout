using Bento.Core;
using Bento.UI;
using Bento.Windows;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;
using static Bento.Tests.Program;

namespace Bento.Tests;

internal static class InteractionTests
{
    public static void RunAll()
    {
        var bounds = new PixelRect(0, 0, 1000, 800); var id = Guid.NewGuid();
        Run("Longer split delay migrates the old default and preserves custom choices", () =>
        {
            Equal(900, new BentoSettings().SplitHoldMs);
            Equal(900, BentoSettings.Parse("{\"SplitHoldMs\":450}").SplitHoldMs);
            Equal(700, BentoSettings.Parse("{\"SplitHoldMs\":700}").SplitHoldMs);
            Equal(450, BentoSettings.Parse("{\"SplitHoldMs\":450,\"SchemaVersion\":2}").SplitHoldMs);
            Check(new BentoSettings(SplitHoldMs: 2000).IsValid);
            var gesture = new DragIntent();
            gesture.Update("A", id, bounds, new(10, 400), 0, 900);
            Check(!gesture.Update("A", id, bounds, new(10, 400), 899, 900).Armed);
            Check(gesture.Update("A", id, bounds, new(10, 400), 900, 900).Armed);
        });
        Run("Slot preview keeps odd pixels and negative monitor origins within the existing slot", () =>
        {
            var slot = new PixelRect(-901, -51, 901, 701);
            Equal(slot, SlotPreview.Bounds(slot, Placement.Center, 8));
            var left = SlotPreview.Bounds(slot, Placement.Left, 8); var right = SlotPreview.Bounds(slot, Placement.Right, 8);
            var top = SlotPreview.Bounds(slot, Placement.Top, 8); var bottom = SlotPreview.Bounds(slot, Placement.Bottom, 8);
            Equal(slot.X, left.X); Equal(slot.Right, right.Right); Equal(left.Right + 8, right.X);
            Equal(slot.Y, top.Y); Equal(slot.Bottom, bottom.Bottom); Equal(top.Bottom + 8, bottom.Y);
        });
        Run("Wallpaper contrast uses black on light colors and white on dark colors", () =>
        {
            Check(WallpaperContrast.UseBlack(255, 255, 255)); Check(!WallpaperContrast.UseBlack(0, 0, 0));
            Check(WallpaperContrast.UseBlack(190, 190, 190)); Check(!WallpaperContrast.UseBlack(55, 55, 55));
        });
        Run("Hold intent starts as a swap, then arms a split at the threshold", () =>
        {
            var gesture = new DragIntent();
            Equal(Placement.Center, gesture.Update("A", id, bounds, new(10,400), 1000,450).Placement);
            Check(!gesture.Update("A", id, bounds, new(12,402), 1449,450).Armed);
            var armed = gesture.Update("A", id, bounds, new(12,402), 1450,450);
            Equal(Placement.Left, armed.Placement); Equal(1d, armed.Progress);
        });
        foreach (var (point, placement) in new[] { (new PixelPoint(10,400), Placement.Left), (new PixelPoint(990,400), Placement.Right), (new PixelPoint(500,10), Placement.Top), (new PixelPoint(500,790), Placement.Bottom) })
            Run($"Hold arms {placement} recursive placement", () =>
            { var g = new DragIntent(); g.Update("A",id,bounds,point,0,450); Equal(placement,g.Update("A",id,bounds,point,500,450).Placement); });
        Run("Edge boundary jitter preserves hold progress", () =>
        {
            var g = new DragIntent(); g.Update("A",id,bounds,new(240,400),0,450);
            Equal(Placement.Left,g.Update("A",id,bounds,new(255,400),500,450).Placement);
        });
        Run("Changing target or leaving the edge resets the hold", () =>
        {
            var g = new DragIntent(); g.Update("A",id,bounds,new(10,400),0,450);
            Check(!g.Update("A",Guid.NewGuid(),bounds,new(10,400),500,450).Armed);
            g.Update("A",id,bounds,new(10,400),600,450); g.Update("A",id,bounds,new(500,400),1100,450);
            Check(!g.Update("A",id,bounds,new(10,400),1200,450).Armed);
            g.Reset(); Check(!g.Update("A",id,bounds,new(10,400),2000,450).Armed);
        });
        Run("Zero hold supports immediate split preference", () => Equal(Placement.Right,new DragIntent().Update("A",id,bounds,new(990,400),0,0).Placement));
        Run("Motion reaches exact negative-origin endpoints without overshoot", () =>
        {
            var from = new PixelRect(-1900,-200,900,600); var to = new PixelRect(100,200,800,500);
            Equal(from,Motion.Interpolate(from,to,0)); Equal(to,Motion.Interpolate(from,to,1));
            for (int i=0;i<=100;i++) { var r=Motion.Interpolate(from,to,i/100d); Check(r.X>=from.X && r.X<=to.X && r.Width>=800 && r.Width<=900); }
        });
        Run("Settings reject unsafe ranges and retain earlier JSON defaults", () =>
        { Check(!new BentoSettings(SplitHoldMs:-1).IsValid); Check(!new BentoSettings(AnimationMs:999).IsValid); Check(JsonSerializer.Deserialize<BentoSettings>("{\"Gap\":12}")!.SplitHoldMs == 900); });
        Run("GitHub repository parsing accepts URLs and rejects arbitrary endpoints", () =>
        {
            Equal("AbdullahEgh/Bento-Layout",UpdateService.NormalizeRepository("https://github.com/AbdullahEgh/Bento-Layout/"));
            Reject(() => UpdateService.NormalizeRepository("https://example.com/token"));
        });
        string temp = Path.Combine(Path.GetTempPath(), "Bento-tests-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(temp);
        try
        {
            Run("Snap takeover restores the exact original value", () =>
            {
                bool enabled = true; string journal = Path.Combine(temp,"snap.txt");
                using (var lease = new SnapLease(journal,()=>enabled,v=>enabled=v)) { lease.SetSuppressed(true); Check(!enabled); lease.SetSuppressed(true); }
                Check(enabled); Check(!File.Exists(journal));
                enabled=false; using(var lease=new SnapLease(journal,()=>enabled,v=>enabled=v)) lease.SetSuppressed(true);
                Check(!enabled);
            });
            Run("Snap recovery restores a crashed session without overwriting a newer choice", () =>
            {
                string journal=Path.Combine(temp,"recovery.txt"); File.WriteAllText(journal,"True"); bool enabled=false;
                using(var lease=new SnapLease(journal,()=>enabled,v=>enabled=v)) Check(enabled);
                File.WriteAllText(journal,"False"); enabled=true;
                using(var lease=new SnapLease(journal,()=>enabled,v=>enabled=v)) Check(enabled);
            });
            string staged=Path.Combine(temp,"staged"); Directory.CreateDirectory(staged);
            var files = new Dictionary<string,string>();
            foreach(string name in new[] { "Bento.exe","Bento.dll","Bento.runtimeconfig.json","Bento.Updater.exe" })
            { File.WriteAllText(Path.Combine(staged,name),"new-"+name); files[name]=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(staged,name)))); }
            File.WriteAllText(Path.Combine(staged,UpdatePackage.ManifestName),JsonSerializer.Serialize(new PackageManifest("Bento.Windows","0.3.0","win-x64",files)));
            Run("Update packages validate every payload hash", () =>
            {
                Equal("0.3.0",UpdatePackage.ValidateDirectory(staged).Version);
                File.WriteAllText(Path.Combine(staged,"Bento.dll"),"tampered"); Reject(()=>UpdatePackage.ValidateDirectory(staged));
                File.WriteAllText(Path.Combine(staged,"Bento.dll"),"new-Bento.dll");
            });
            Run("Update extraction rejects traversal before writing payloads", () =>
            {
                string zip=Path.Combine(temp,"bad.zip"); using(var archive=ZipFile.Open(zip,ZipArchiveMode.Create)) archive.CreateEntry("../outside.exe");
                Reject(()=>UpdatePackage.Extract(zip,Path.Combine(temp,"bad"))); Check(!File.Exists(Path.Combine(temp,"outside.exe")));
            });
            Run("Update extraction rejects case-insensitive duplicate paths", () =>
            {
                string zip=Path.Combine(temp,"duplicate.zip"); using(var archive=ZipFile.Open(zip,ZipArchiveMode.Create)) { archive.CreateEntry("Bento.dll"); archive.CreateEntry("bento.DLL"); }
                Reject(()=>UpdatePackage.Extract(zip,Path.Combine(temp,"duplicate")));
            });
            Run("Failed update launch restores every replaced application file", () =>
            {
                string target=Path.Combine(temp,"installed");Directory.CreateDirectory(target);
                File.WriteAllText(Path.Combine(target,"Bento.exe"),"original");
                Reject(()=>UpdateInstaller.Apply(staged,target,Path.Combine(temp,"backup"),()=>throw new IOException("simulated startup failure")));
                Equal("original",File.ReadAllText(Path.Combine(target,"Bento.exe"))); Check(!File.Exists(Path.Combine(target,"Bento.dll")));
            });
            Run("Successful update replaces application files and retains backup", () =>
            {
                string target=Path.Combine(temp,"success");Directory.CreateDirectory(target); File.WriteAllText(Path.Combine(target,"Bento.exe"),"original");
                string backup=Path.Combine(temp,"success-backup"); UpdateInstaller.Apply(staged,target,backup);
                Equal("new-Bento.exe",File.ReadAllText(Path.Combine(target,"Bento.exe"))); Equal("original",File.ReadAllText(Path.Combine(backup,"Bento.exe")));
            });
        }
        finally { if(Path.GetFullPath(temp).StartsWith(Path.GetFullPath(Path.GetTempPath()),StringComparison.OrdinalIgnoreCase)) Directory.Delete(temp,true); }
    }
    private static void Reject(Action action) { try { action(); } catch (Exception ex) when (ex is ArgumentException or InvalidDataException or IOException) { return; } throw new Exception("Expected rejection."); }
}
