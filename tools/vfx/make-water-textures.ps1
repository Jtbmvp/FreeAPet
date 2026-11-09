# Generates the water VFX textures used by the V6 waterfall, lake and spawn fountain.
#   water_streaks.png : 128x512, white streaks with alpha, tiles vertically (Beam texture, scrolled).
#   water_ripple.png  : 128x128, soft ring (flat ParticleEmitter for lake ripples).
# Usage: pwsh tools/vfx/make-water-textures.ps1 -OutDir build/vfx
param([string] $OutDir = 'build/vfx', [int] $Seed = 6)
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$rng = [System.Random]::new($Seed)

# --- streaks -------------------------------------------------------------
$w = 128; $h = 512
$bmp = [System.Drawing.Bitmap]::new($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$alpha = New-Object 'double[,]' $w, $h
# base sheet: soft columns of varying density
$col = New-Object 'double[]' $w
for ($x = 0; $x -lt $w; $x++) { $col[$x] = 0.18 + 0.22 * $rng.NextDouble() }
for ($pass = 0; $pass -lt 2; $pass++) {
    $tmp = $col.Clone()
    for ($x = 0; $x -lt $w; $x++) { $col[$x] = ($tmp[($x - 1 + $w) % $w] + $tmp[$x] * 2 + $tmp[($x + 1) % $w]) / 4 }
}
for ($x = 0; $x -lt $w; $x++) { for ($y = 0; $y -lt $h; $y++) { $alpha[$x, $y] = $col[$x] } }
# bright streaks that wrap vertically
for ($i = 0; $i -lt 70; $i++) {
    $sx = $rng.Next(0, $w); $sy = $rng.Next(0, $h); $len = $rng.Next(60, 260); $sw = $rng.Next(1, 4)
    $peak = 0.45 + 0.5 * $rng.NextDouble()
    for ($k = 0; $k -lt $len; $k++) {
        $t = $k / $len; $a = $peak * [Math]::Sin([Math]::PI * $t)
        for ($d = -$sw; $d -le $sw; $d++) {
            $xx = ($sx + $d + $w) % $w; $yy = ($sy + $k) % $h
            $fall = 1 - [Math]::Abs($d) / ($sw + 1)
            $alpha[$xx, $yy] = [Math]::Min(1, $alpha[$xx, $yy] + $a * $fall)
        }
    }
}
for ($x = 0; $x -lt $w; $x++) {
    for ($y = 0; $y -lt $h; $y++) {
        $a = [int][Math]::Round(255 * [Math]::Min(1, $alpha[$x, $y]))
        $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($a, 255, 255, 255))
    }
}
$bmp.Save((Join-Path $OutDir 'water_streaks.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

# --- ripple ring ---------------------------------------------------------
$s = 128
$rip = [System.Drawing.Bitmap]::new($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$c = ($s - 1) / 2
for ($x = 0; $x -lt $s; $x++) {
    for ($y = 0; $y -lt $s; $y++) {
        $r = [Math]::Sqrt(($x - $c) * ($x - $c) + ($y - $c) * ($y - $c)) / $c
        $ring = [Math]::Exp(-[Math]::Pow(($r - 0.82) / 0.07, 2)) + 0.35 * [Math]::Exp(-[Math]::Pow(($r - 0.62) / 0.05, 2))
        $a = [int][Math]::Round(255 * [Math]::Min(1, $ring))
        $rip.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($a, 255, 255, 255))
    }
}
$rip.Save((Join-Path $OutDir 'water_ripple.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$rip.Dispose()
Get-ChildItem $OutDir | Select-Object Name, Length
