# ============================================================
# توليد حمولة GitHub من مجلد المصدر — نسخة PowerShell لويندوز
# الاستخدام:  .\make_payload.ps1 -Src "C:\path\to\src_app"
# يتطلب: git مثبتاً (Git for Windows)
# ============================================================
param([Parameter(Mandatory=$true)][string]$Src)
$ErrorActionPreference = "Stop"
Set-Location $Src
$Out = Join-Path (Split-Path $Src -Parent) "payload"
if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item -ItemType Directory -Path $Out | Out-Null

# أرشيف نظيف من git (الأسرار غير متتبعة أصلاً)
git archive --format=zip -o "$Out\proj.zip" HEAD
$hash = (Get-FileHash "$Out\proj.zip" -Algorithm SHA256).Hash.ToLower()
Write-Host "sha256 (احفظه للتحقق): $hash"

# فحص أمان
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead("$Out\proj.zip")
$bad = $zip.Entries | Where-Object { $_.FullName -match '\.jks$|dev_keystore|(^|/)cloud\.env$' }
$zip.Dispose()
if ($bad) { Write-Error "⚠️ خطر: أسرار داخل الأرشيف — أوقف الرفع!"; exit 1 }
Write-Host "✓ الأرشيف خالٍ من الأسرار"

# base64 ثم التقسيم إلى 5 أجزاء متساوية تقريباً
$bytes = [IO.File]::ReadAllBytes("$Out\proj.zip")
$b64 = [Convert]::ToBase64String($bytes)
$len = $b64.Length; $size = [math]::Ceiling($len / 5)
for ($i = 0; $i -lt 5; $i++) {
  $start = $i * $size
  $chunk = if ($start -lt $len) { $b64.Substring($start, [math]::Min($size, $len - $start)) } else { "" }
  $name = "proj.b64.part{0:D2}" -f $i
  [IO.File]::WriteAllText("$Out\$name", $chunk)
  Write-Host "  $name  $($chunk.Length) حرفاً"
}
Write-Host "✓ ارفع الأجزاء الخمسة إلى _bootstrap/ في المستودع (استبدالاً)"
