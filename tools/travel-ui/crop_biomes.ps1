# Crop Studio captures of each biome to 512x288 PNG cards for the Travel panel.
# Usage: crop_biomes.ps1 <captures dir> <output dir>
param([string]$Src, [string]$Out)
Add-Type -AssemblyName System.Drawing
# name = capture file, horizontal centre 0..1, vertical centre 0..1, zoom
$shots = [ordered]@{
  kingdom = @('mcp-Roblox_Studio-blob-1795724833458-83mes9.jpg', 0.47, 0.50, 1.15)
  desert  = @('mcp-Roblox_Studio-blob-1795724841394-uclqkh.jpg', 0.50, 0.55, 1.10)
  ice     = @('mcp-Roblox_Studio-blob-1795724845786-4mcltk.jpg', 0.50, 0.50, 1.10)
  forest  = @('mcp-Roblox_Studio-blob-1795724850522-fj56l0.jpg', 0.52, 0.50, 1.05)
  lobby   = @('mcp-Roblox_Studio-blob-1795724855185-fzq6fj.jpg', 0.50, 0.52, 1.10)
  base    = @('mcp-Roblox_Studio-blob-1795724867120-469elj.jpg', 0.55, 0.55, 1.00)
}
foreach ($name in $shots.Keys) {
  $f, $cx, $cy, $zoom = $shots[$name]
  $im = [System.Drawing.Image]::FromFile((Join-Path $Src $f))
  $ch = $im.Height / $zoom; $cw = $ch * 16 / 9
  $x0 = [Math]::Min([Math]::Max($cx * $im.Width - $cw / 2, 0), $im.Width - $cw)
  $y0 = [Math]::Min([Math]::Max($cy * $im.Height - $ch / 2, 0), $im.Height - $ch)
  $bmp = New-Object System.Drawing.Bitmap 512, 288
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
  $g.DrawImage($im, (New-Object System.Drawing.Rectangle 0, 0, 512, 288), [float]$x0, [float]$y0, [float]$cw, [float]$ch, 'Pixel')
  $bmp.Save((Join-Path $Out "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose(); $im.Dispose()
  "$name ok"
}
