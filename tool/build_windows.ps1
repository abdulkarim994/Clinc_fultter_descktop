# ============================================================================
#  بناء نسخة ويندوز: release ثم حزمة MSIX — نظير PowerShell لـ build_windows.bat
#  انظر WINDOWS_DEPLOY_AR.md للدليل الكامل.
#
#  الاستخدام (من جذر المشروع):
#      pwsh tool\build_windows.ps1            بناء موصول بالسحابة إن توفّر cloud.env
#      pwsh tool\build_windows.ps1 -Local     بناء محلي صريح (بلا أسرار سحابية)
#
#  الأسرار تُقرأ من tool\cloud.env (مستثنى من git) أو من متغيّرات البيئة
#  المضبوطة سلفاً. لا سرّ ثابت في هذا الملف — توأمَ نمطِ build_cloud.
#  غياب الأسرار تحذير لا خطأ: نسخة سطح المكتب تعمل بوضع محلي بلا سحابة.
# ============================================================================
param([switch]$Local)

$ErrorActionPreference = 'Stop'

# حمّل tool\cloud.env إلى متغيّرات البيئة إن وُجد (سطور KEY=VALUE، # تعليق).
$envFile = Join-Path $PSScriptRoot 'cloud.env'
if (Test-Path $envFile) {
  Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
      $k, $v = $line.Split('=', 2)
      Set-Item -Path "Env:$($k.Trim())" -Value $v.Trim()
    }
  }
}

$defines = @()
if ($Local) {
  Write-Host '[i] بناء محلي صريح: تُتجاهل أي أسرار سحابية.'
} elseif ($env:SUPABASE_URL -and $env:SUPABASE_ANON_KEY) {
  # الأعلام يجب أن تطابق الخلفية التي كُتبت بها البيانات — مثل build_cloud.
  if (-not $env:PHONE_IDENTITY) { $env:PHONE_IDENTITY = '1' }
  if (-not $env:COLD_FETCH)     { $env:COLD_FETCH = '1' }
  $defines = @(
    "--dart-define=SUPABASE_URL=$($env:SUPABASE_URL)",
    "--dart-define=SUPABASE_ANON_KEY=$($env:SUPABASE_ANON_KEY)",
    "--dart-define=R2_WORKER=$($env:R2_WORKER)",
    "--dart-define=PHONE_IDENTITY=$($env:PHONE_IDENTITY)",
    "--dart-define=COLD_FETCH=$($env:COLD_FETCH)"
  )
  Write-Host '[i] بناء موصول بالسحابة: حُقنت أسرار Supabase/R2.'
} else {
  Write-Host '[!] لا أسرار سحابية (SUPABASE_URL/ANON_KEY) — بناء بوضع محلي.'
  Write-Host '    املأ tool\cloud.env لبناء موصول، أو مرّر -Local لإسكات هذا.'
}

Write-Host ''
Write-Host '=== [1/2] flutter build windows --release ==='
flutter build windows --release @defines
if ($LASTEXITCODE -ne 0) { Write-Error 'فشل بناء ويندوز.'; exit 1 }

Write-Host ''
Write-Host '=== [2/2] dart run msix:create ==='
# التوقيع للنشر: اضبط certificate_path/password في msix_config بشهادة حقيقية،
# أو self-signed للتجربة (WINDOWS_DEPLOY_AR.md). بلا شهادة تُنتَج حزمة غير موقَّعة.
dart run msix:create
if ($LASTEXITCODE -ne 0) { Write-Error 'فشل إنشاء MSIX.'; exit 1 }

Write-Host ''
Write-Host '[✓] تمّ. الناتج في:'
Write-Host '    build\windows\x64\runner\Release\       (EXE + DLLs)'
Write-Host '    build\windows\x64\runner\Release\*.msix (الحزمة)'
