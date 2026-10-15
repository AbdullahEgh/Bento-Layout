$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$taskAssetPath = Join-Path $PSScriptRoot '../src/Bento.UI/Assets'
[IO.Directory]::CreateDirectory($taskAssetPath) | Out-Null
function New-RoundedPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $taskPath = [Drawing.Drawing2D.GraphicsPath]::new()
    $d = 2 * $r
    $taskPath.AddArc($x, $y, $d, $d, 180, 90)
    $taskPath.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $taskPath.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $taskPath.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $taskPath.CloseFigure()
    return $taskPath
}
$taskMaster = [Drawing.Bitmap]::new(1024, 1024)
$g = [Drawing.Graphics]::FromImage($taskMaster)
$g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([Drawing.Color]::Transparent)
$taskBase = [Drawing.Drawing2D.LinearGradientBrush]::new([Drawing.Rectangle]::new(56,56,912,912), [Drawing.ColorTranslator]::FromHtml('#55CFB8'), [Drawing.ColorTranslator]::FromHtml('#18796E'), 65)
$taskOutline = New-RoundedPath 56 56 912 912 218
$g.FillPath($taskBase, $taskOutline)
$taskHighlight = [Drawing.Pen]::new([Drawing.Color]::FromArgb(65,255,255,255),3)
$g.DrawPath($taskHighlight, $taskOutline)
foreach ($r in @(@(226,234,244,556), @(510,234,288,242), @(510,516,288,274))) {
    $taskShadowPath = New-RoundedPath $r[0] ($r[1]+10) $r[2] $r[3] 44
    $taskShadow = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(35,6,68,60))
    $g.FillPath($taskShadow,$taskShadowPath)
    $taskPane = New-RoundedPath $r[0] $r[1] $r[2] $r[3] 44
    $taskFill = [Drawing.Drawing2D.LinearGradientBrush]::new([Drawing.Rectangle]::new($r[0],$r[1],$r[2],$r[3]), [Drawing.Color]::White, [Drawing.ColorTranslator]::FromHtml('#DBF5EE'),90)
    $g.FillPath($taskFill,$taskPane)
    $taskFill.Dispose(); $taskPane.Dispose(); $taskShadow.Dispose(); $taskShadowPath.Dispose()
}
$g.Dispose(); $taskBase.Dispose(); $taskOutline.Dispose(); $taskHighlight.Dispose()
$taskMaster.Save((Join-Path $taskAssetPath 'bento.png'),[Drawing.Imaging.ImageFormat]::Png)
$taskSizes = @(16,24,32,48,64,128,256)
$taskImages = [Collections.Generic.List[byte[]]]::new()
foreach ($size in $taskSizes) {
    $taskBitmap = [Drawing.Bitmap]::new($size,$size)
    $taskGraphics = [Drawing.Graphics]::FromImage($taskBitmap)
    $taskGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $taskGraphics.DrawImage($taskMaster,0,0,$size,$size)
    $taskStream = [IO.MemoryStream]::new()
    $taskBitmap.Save($taskStream,[Drawing.Imaging.ImageFormat]::Png)
    $taskImages.Add($taskStream.ToArray())
    $taskStream.Dispose(); $taskGraphics.Dispose(); $taskBitmap.Dispose()
}
$taskIconStream = [IO.File]::Create((Join-Path $taskAssetPath 'bento.ico'))
$writer = [IO.BinaryWriter]::new($taskIconStream)
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$taskSizes.Length)
$offset = 6 + 16 * $taskSizes.Length
for ($i=0; $i -lt $taskSizes.Length; $i++) {
    $sizeByte = if ($taskSizes[$i] -eq 256) { 0 } else { $taskSizes[$i] }
    $writer.Write([byte]$sizeByte); $writer.Write([byte]$sizeByte); $writer.Write([byte]0); $writer.Write([byte]0)
    $writer.Write([uint16]1); $writer.Write([uint16]32); $writer.Write([uint32]$taskImages[$i].Length); $writer.Write([uint32]$offset)
    $offset += $taskImages[$i].Length
}
foreach ($bytes in $taskImages) { $writer.Write($bytes) }
$writer.Dispose(); $taskMaster.Dispose()
Write-Output 'Created Bento SVG companion PNG and multi-resolution Windows icon.'
