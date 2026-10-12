# Domokoncept /brag-slim — deterministic frame renderer (GDI+)
# Every frame is a pure function of time t = f/fps. Outputs JPEG frames.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$BASE   = 'C:\Users\barcz\Documents\Domokoncept\DomokonceptWebsite'
$IMG    = Join-Path $BASE 'site\images'
$FRAMES = Join-Path $BASE 'brag-output\work\frames'
$W=1920; $H=1080; $FPS=30
$TOTAL = 20.4
$N = [int][Math]::Round($TOTAL*$FPS)   # 612

# ---------- palette ----------
function C([int]$r,[int]$g,[int]$b,[double]$a=1.0){ [System.Drawing.Color]::FromArgb([int][Math]::Round(255*$a),$r,$g,$b) }
$paper = C 244 242 237
$ink   = C 26 23 18
$accent= C 157 114 86
$muted = C 134 127 116
$line  = C 232 228 219
$cream = C 245 242 236

# ---------- fonts ----------
$ffLight = New-Object System.Drawing.FontFamily('Segoe UI Light')
$ffSemil = New-Object System.Drawing.FontFamily('Segoe UI Semilight')
$ffReg   = New-Object System.Drawing.FontFamily('Segoe UI')
$ffSemi  = New-Object System.Drawing.FontFamily('Segoe UI Semibold')
function Font($fam,[double]$size,$style=[System.Drawing.FontStyle]::Regular){ New-Object System.Drawing.Font($fam,[single]$size,$style,[System.Drawing.GraphicsUnit]::Pixel) }

# ---------- images ----------
$imgCache=@{}
function Img($name){ if(-not $imgCache.ContainsKey($name)){ $imgCache[$name]=[System.Drawing.Image]::FromFile((Join-Path $IMG $name)) }; $imgCache[$name] }

# ---------- easing ----------
function Clamp01([double]$x){ if($x -lt 0){0.0}elseif($x -gt 1){1.0}else{$x} }
function EaseOut([double]$x){ $x=Clamp01 $x; 1-[Math]::Pow(1-$x,3) }
function EaseInOut([double]$x){ $x=Clamp01 $x; if($x -lt 0.5){4*$x*$x*$x}else{1-[Math]::Pow(-2*$x+2,3)/2} }

# scene content alpha: fade in from paper, fade out to paper
function SceneAlpha([double]$lt,[double]$dur,[double]$inD,[double]$outD){
  $a=1.0
  if($inD -gt 0 -and $lt -lt $inD){ $a=EaseOut($lt/$inD) }
  if($outD -gt 0){ $rem=$dur-$lt; if($rem -lt $outD){ $a=[Math]::Min($a,(EaseOut($rem/$outD))) } }
  Clamp01 $a
}

# ---------- drawing helpers ----------
function CoverRect($g,$img,[double]$dx,[double]$dy,[double]$dw,[double]$dh,[double]$zoom,[double]$ox,[double]$oy,[double]$alpha){
  if($alpha -le 0.001){return}
  $iw=$img.Width; $ih=$img.Height
  $cover=[Math]::Max($dw/$iw,$dh/$ih)*$zoom
  $sw=$dw/$cover; $sh=$dh/$cover
  $sx=($iw-$sw)/2 + $ox; $sy=($ih-$sh)/2 + $oy
  if($sx -lt 0){$sx=0}; if($sy -lt 0){$sy=0}
  if($sx+$sw -gt $iw){$sx=$iw-$sw}; if($sy+$sh -gt $ih){$sy=$ih-$sh}
  $cm=New-Object System.Drawing.Imaging.ColorMatrix
  $cm.Matrix33=[single]$alpha
  $ia=New-Object System.Drawing.Imaging.ImageAttributes
  $ia.SetColorMatrix($cm)
  $dest=New-Object System.Drawing.Rectangle([int]$dx,[int]$dy,[int][Math]::Ceiling($dw),[int][Math]::Ceiling($dh))
  $g.DrawImage($img,$dest,[single]$sx,[single]$sy,[single]$sw,[single]$sh,[System.Drawing.GraphicsUnit]::Pixel,$ia)
  $ia.Dispose()
}

function VeilLinear($g,[double]$alpha,[int]$top,[int]$bottom,[double]$topA,[double]$botA){
  if($alpha -le 0.001){return}
  $rect=New-Object System.Drawing.Rectangle(0,$top,$W,($bottom-$top))
  $c1=[System.Drawing.Color]::FromArgb([int][Math]::Round(255*$topA*$alpha),0,0,0)
  $c2=[System.Drawing.Color]::FromArgb([int][Math]::Round(255*$botA*$alpha),0,0,0)
  $lb=New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect,$c1,$c2,[System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
  $g.FillRectangle($lb,$rect); $lb.Dispose()
}
function VeilFlat($g,[double]$a){ if($a -le 0.001){return}; $b=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb([int][Math]::Round(255*$a),0,0,0)); $g.FillRectangle($b,0,0,$W,$H); $b.Dispose() }

$sfType=New-Object System.Drawing.StringFormat([System.Drawing.StringFormat]::GenericTypographic)
function TextW($g,$s,$font){ ($g.MeasureString($s,$font,[System.Drawing.PointF]::Empty,$sfType)).Width }

# centered plain line
function DrawCenter($g,$s,$font,$col,[double]$cx,[double]$y,[double]$alpha){
  if($alpha -le 0.004){return}
  $w=TextW $g $s $font
  $b=New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb([int][Math]::Round(255*$alpha),$col.R,$col.G,$col.B))
  $g.DrawString($s,$font,$b,[single]($cx-$w/2),[single]$y,$sfType); $b.Dispose()
}
function DrawLeft($g,$s,$font,$col,[double]$x,[double]$y,[double]$alpha){
  if($alpha -le 0.004){return}
  $b=New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb([int][Math]::Round(255*$alpha),$col.R,$col.G,$col.B))
  $g.DrawString($s,$font,$b,[single]$x,[single]$y,$sfType); $b.Dispose()
}
# letter-tracked, optionally centered
function DrawTracked($g,$s,$font,$col,[double]$x,[double]$y,[double]$alpha,[double]$track,[bool]$center=$false){
  if($alpha -le 0.004){return}
  $xtra=$track*2.0   # widen spaces so tracked words don't collapse
  $chars=$s.ToCharArray()
  $tot=0.0; foreach($ch in $chars){ $adv=(TextW $g ([string]$ch) $font)+$track; if($ch -eq ' '){$adv+=$xtra}; $tot+=$adv }
  $tot -= $track
  $sx=$x; if($center){ $sx=$x-$tot/2 }
  $b=New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb([int][Math]::Round(255*$alpha),$col.R,$col.G,$col.B))
  $cur=$sx
  foreach($ch in $chars){ $cw=TextW $g ([string]$ch) $font; $g.DrawString([string]$ch,$font,$b,[single]$cur,[single]$y,$sfType); $adv=$cw+$track; if($ch -eq ' '){$adv+=$xtra}; $cur += $adv }
  $b.Dispose()
}
# exact advance width DrawTracked consumes (for seamless marquee tiling)
function TrackedAdvance($g,$s,$font,[double]$track){
  $xtra=$track*2.0; $sum=0.0
  foreach($ch in $s.ToCharArray()){ $adv=(TextW $g ([string]$ch) $font)+$track; if($ch -eq ' '){$adv+=$xtra}; $sum+=$adv }
  $sum
}

# ---------- fonts instances ----------
$fEyebrow = Font $ffSemi 23
$fH1      = Font $ffLight 112
$fH1b     = Font $ffLight 88
$fLead    = Font $ffSemil 36
$fBody    = Font $ffReg 30
$fWord    = Font $ffSemil 128
$fWordSm  = Font $ffSemi 30
$fNum     = Font $ffLight 150
$fStatLab = Font $ffSemi 22
$fTileLab = Font $ffSemi 30
$fOutro   = Font $ffLight 96
$fFine    = Font $ffReg 26

# ---------- scene draws ----------
function Scene1($g,[double]$lt,[double]$dur){
  $ca=SceneAlpha $lt $dur 0.5 0.4
  $zoom=1.02 + 0.07*(EaseInOut($lt/$dur))
  CoverRect $g (Img 'hero-loft.jpg') 0 0 $W $H $zoom 0 0 $ca
  VeilLinear $g $ca 420 $H 0.0 0.72
  VeilFlat $g (0.08*$ca)
  $cx=$W/2
  $e=EaseOut((($lt-0.35)/0.7)); $ey=(1-$e)*22
  DrawTracked $g 'SALON MEBLOWY  ·  SZCZECIN' $fEyebrow $cream $cx (760+$ey) ($ca*$e) 7 $true
  $h=EaseOut((($lt-0.7)/0.9)); $hy=(1-$h)*34
  DrawCenter $g '…inna strona wnętrza' $fH1 $cream $cx (800+$hy) ($ca*$h)
}

function Scene2($g,[double]$lt,[double]$dur){
  $ca=SceneAlpha $lt $dur 0.45 0.4
  $cx=$W/2
  $w=EaseOut((($lt-0.25)/0.8)); $wy=(1-$w)*40
  DrawTracked $g 'DOMOKONCEPT' $fWord $ink ($cx) (420+$wy) ($ca*$w) 10 $true
  # accent rule grows
  $rg=EaseOut((($lt-0.7)/0.7))
  if($ca*$rg -gt 0.01){
    $rw=240*$rg
    $rb=New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb([int][Math]::Round(255*$ca),$accent.R,$accent.G,$accent.B))
    $g.FillRectangle($rb,[single]($cx-$rw/2),[single]610,[single]$rw,[single]3); $rb.Dispose()
  }
  $s=EaseOut((($lt-1.0)/0.8)); $sy=(1-$s)*22
  DrawCenter $g 'Meble, które tworzą dom.' $fLead $muted $cx (646+$sy) ($ca*$s)
}

function Scene3($g,[double]$lt,[double]$dur){
  $ca=SceneAlpha $lt $dur 0.45 0.4
  $zoom=1.02 + 0.06*(EaseInOut($lt/$dur))
  CoverRect $g (Img 'hero-belle.jpg') 0 0 $W $H $zoom 0 0 $ca
  # left-side scrim panel for text
  if($ca -gt 0.01){
    $rect=New-Object System.Drawing.Rectangle(0,0,1120,$H)
    $c1=[System.Drawing.Color]::FromArgb([int][Math]::Round(255*0.70*$ca),0,0,0)
    $c2=[System.Drawing.Color]::FromArgb(0,0,0,0)
    $lb=New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect,$c1,$c2,[System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $g.FillRectangle($lb,$rect); $lb.Dispose()
  }
  $x=150
  $e=EaseOut((($lt-0.3)/0.7)); $ey=(1-$e)*20
  DrawTracked $g 'DLACZEGO MY' $fEyebrow $accent $x (360+$ey) ($ca*$e) 6 $false
  $h=EaseOut((($lt-0.55)/0.8)); $hy=(1-$h)*30
  DrawLeft $g 'Nie urządzamy się' $fH1b $cream $x (410+$hy) ($ca*$h)
  DrawLeft $g 'jak typowy sklep.' $fH1b $cream $x (508+$hy) ($ca*$h)
  $s=EaseOut((($lt-1.1)/0.9)); $sy=(1-$s)*18
  DrawLeft $g 'Meble w naturalnych aranżacjach.' $fBody $cream $x (640+$sy) ($ca*$s*0.92)
  DrawLeft $g 'Usiądź, dotknij, napij się kawy.' $fBody $cream $x (686+$sy) ($ca*$s*0.92)
}

function Scene4($g,[double]$lt,[double]$dur){
  $ca=SceneAlpha $lt $dur 0.45 0.4
  $g.Clear($paper)  # redundant safety; main loop clears
  $cx=$W/2
  $e=EaseOut((($lt-0.2)/0.7)); $ey=(1-$e)*18
  DrawTracked $g 'DOMOKONCEPT W LICZBACH' $fEyebrow $accent $cx (250+$ey) ($ca*$e) 7 $true
  $stats=@(@(775,'PRODUKTÓW'),@(9,'MAREK PREMIUM'),@(5,'MIN OD CENTRUM'))
  $cols=@(($W*0.26),($W*0.5),($W*0.74))
  for($i=0;$i -lt 3;$i++){
    $d=0.35+$i*0.12
    $p=EaseOut((($lt-$d)/1.1))
    $val=[int][Math]::Round($stats[$i][0]*$p)
    DrawCenter $g ([string]$val) $fNum $ink $cols[$i] 380 ($ca)
    DrawTracked $g $stats[$i][1] $fStatLab $muted $cols[$i] 586 ($ca*(EaseOut((($lt-$d-0.2)/0.6)))) 4 $true
    if($i -lt 2){
      $dvA=$ca*(EaseOut((($lt-0.5)/0.7)))
      if($dvA -gt 0.01){ $db=New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb([int][Math]::Round(255*$dvA),$line.R,$line.G,$line.B)); $mid=($cols[$i]+$cols[$i+1])/2; $g.FillRectangle($db,[single]$mid,[single]410,[single]1,[single]150); $db.Dispose() }
    }
  }
  # drifting brand row
  $bA=$ca*(EaseOut((($lt-0.8)/0.9)))
  if($bA -gt 0.01){
    $brands='Vilmers   SITS   Comforty   Flexlux   Selfia   Take me home   Szyszka   FAMEG   '
    $g.SetClip((New-Object System.Drawing.Rectangle(0,720,$W,90)))
    $drift = - (($lt-0.8)*46)
    $one=TrackedAdvance $g $brands $fWordSm 3
    $startx = $cx - $one + ($drift % $one)
    for($k=-1;$k -le 3;$k++){ DrawTracked $g $brands $fWordSm $muted ($startx + $k*$one) 742 ($bA*0.9) 3 $false }
    $g.ResetClip()
  }
}

function Scene5($g,[double]$lt,[double]$dur){
  $ca=SceneAlpha $lt $dur 0.45 0.4
  $cx=$W/2
  $e=EaseOut((($lt-0.15)/0.6)); $ey=(1-$e)*16
  DrawTracked $g 'KOLEKCJE' $fEyebrow $accent $cx (150+$ey) ($ca*$e) 8 $true
  DrawCenter $g 'Polski i skandynawski design' $fH1b $ink $cx (196+$ey) ($ca*(EaseOut((($lt-0.3)/0.7))))
  $tiles=@(@('cat-sofy.jpg','SOFY'),@('cat-stoly.jpg','STOŁY'),@('cat-krzesla.jpg','KRZESŁA'),@('cat-lampy.jpg','OŚWIETLENIE'))
  $tw=360; $th=360; $gap=42
  $totalw=4*$tw+3*$gap
  $x0=($W-$totalw)/2; $y0=470
  for($i=0;$i -lt 4;$i++){
    $d=0.35+$i*0.14
    $p=EaseOut((($lt-$d)/0.75)); if($p -le 0.001){continue}
    $ty=$y0 + (1-$p)*40
    $ax=$ca*$p
    $tx=$x0+$i*($tw+$gap)
    $clip=New-Object System.Drawing.Rectangle([int]$tx,[int]$ty,$tw,$th)
    $g.SetClip($clip)
    CoverRect $g (Img $tiles[$i][0]) $tx $ty $tw $th 1.04 0 0 $ax
    # label bar
    VeilLinearRect $g $clip $ax 0.0 0.80 200
    $g.ResetClip()
    DrawTracked $g $tiles[$i][1] $fTileLab $cream ($tx+$tw/2) ($ty+$th-54) $ax 4 $true
    # thin border
    $pen=New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb([int][Math]::Round(255*$ax*0.4),$line.R,$line.G,$line.B)),1
    $g.DrawRectangle($pen,[int]$tx,[int]$ty,$tw,$th); $pen.Dispose()
  }
}
function VeilLinearRect($g,$rect,[double]$alpha,[double]$topA,[double]$botA,[int]$bandH){
  if($alpha -le 0.004){return}
  $r=New-Object System.Drawing.Rectangle($rect.X,($rect.Y+$rect.Height-$bandH),$rect.Width,$bandH)
  $c1=[System.Drawing.Color]::FromArgb([int][Math]::Round(255*$topA*$alpha),0,0,0)
  $c2=[System.Drawing.Color]::FromArgb([int][Math]::Round(255*$botA*$alpha),0,0,0)
  $lb=New-Object System.Drawing.Drawing2D.LinearGradientBrush($r,$c1,$c2,[System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
  $g.FillRectangle($lb,$r); $lb.Dispose()
}

function Scene6($g,[double]$lt,[double]$dur){
  $ca=SceneAlpha $lt $dur 0.5 0.0   # no fade-out: hold end card
  $zoom=1.08 - 0.05*(EaseInOut($lt/$dur))
  CoverRect $g (Img 'hero-alps.jpg') 0 0 $W $H $zoom 0 0 $ca
  VeilFlat $g (0.60*$ca)
  $cx=$W/2
  $shadow = C 8 7 5
  $h=EaseOut((($lt-0.3)/0.9)); $hy=(1-$h)*26
  DrawCenter $g 'Poczuj się jak u siebie w domu.' $fOutro $shadow ($cx+2) (396+$hy) ($ca*$h*0.55)
  DrawCenter $g 'Poczuj się jak u siebie w domu.' $fOutro $cream $cx (392+$hy) ($ca*$h)
  # lockup
  $l=EaseOut((($lt-1.5)/0.9))
  if($ca*$l -gt 0.01){
    DrawTracked $g 'DOMOKONCEPT' (Font $ffSemi 46) $shadow ($cx+1.5) 561.5 ($ca*$l*0.55) 8 $true
    DrawTracked $g 'DOMOKONCEPT' (Font $ffSemi 46) $cream $cx 560 ($ca*$l) 8 $true
    $rw=200
    $rb=New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb([int][Math]::Round(255*$ca*$l),$accent.R,$accent.G,$accent.B))
    $g.FillRectangle($rb,[single]($cx-$rw/2),[single]636,[single]$rw,[single]2); $rb.Dispose()
    DrawTracked $g 'SZCZECIN  ·  DOMOKONCEPT.PL' $fFine $cream $cx 664 ($ca*$l) 4 $true
    DrawTracked $g 'RATY 0%  ·  DARMOWA DOSTAWA W SZCZECINIE' (Font $ffReg 21) ([System.Drawing.Color]::FromArgb(255,210,204,196)) $cx 712 ($ca*$l*0.9) 3 $true
  }
}

# ---------- main loop ----------
$bmp=New-Object System.Drawing.Bitmap($W,$H,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g=[System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode=[System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.TextRenderingHint=[System.Drawing.Text.TextRenderingHint]::AntiAlias
$g.CompositingQuality=[System.Drawing.Drawing2D.CompositingQuality]::HighQuality

# jpeg encoder q95
$enc=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep=New-Object System.Drawing.Imaging.EncoderParameters(1)
$ep.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality,[long]95)

# boundaries
$b=@(0.0,3.2,6.6,10.2,13.8,16.8,20.4)
$sw=[System.Diagnostics.Stopwatch]::StartNew()
for($f=0;$f -lt $N;$f++){
  $t=$f/$FPS
  $g.Clear($paper)
  if($t -lt $b[1]){ Scene1 $g ($t-$b[0]) ($b[1]-$b[0]) }
  elseif($t -lt $b[2]){ Scene2 $g ($t-$b[1]) ($b[2]-$b[1]) }
  elseif($t -lt $b[3]){ Scene3 $g ($t-$b[2]) ($b[3]-$b[2]) }
  elseif($t -lt $b[4]){ Scene4 $g ($t-$b[3]) ($b[4]-$b[3]) }
  elseif($t -lt $b[5]){ Scene5 $g ($t-$b[4]) ($b[5]-$b[4]) }
  else{ Scene6 $g ($t-$b[5]) ($b[6]-$b[5]) }
  $fn=Join-Path $FRAMES ('f{0:D4}.jpg' -f $f)
  $bmp.Save($fn,$enc,$ep)
}
$sw.Stop()
$g.Dispose(); $bmp.Dispose()
Write-Output ("Rendered {0} frames in {1:N1}s" -f $N,$sw.Elapsed.TotalSeconds)
