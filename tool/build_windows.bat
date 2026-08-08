@echo off
setlocal enabledelayedexpansion
rem ============================================================================
rem  بناء نسخة ويندوز: release ثم حزمة MSIX — انظر WINDOWS_DEPLOY_AR.md
rem
rem  الاستخدام:
rem      tool\build_windows.bat            بناء موصول بالسحابة إن توفّر cloud.env
rem      tool\build_windows.bat --local    بناء محلي صريح (بلا أسرار سحابية)
rem
rem  الأسرار تُقرأ من tool\cloud.env (مستثنى من git — انسخ cloud.env.example
rem  واملأه) أو من متغيّرات البيئة إن ضُبطت سلفاً. لا سرّ ثابت في هذا الملف —
rem  توأمَ نمطِ tool\build_cloud.bat وحارسِ الأسرار في CI.
rem
rem  فرقٌ مقصود عن build_cloud.bat: غياب الأسرار هنا **تحذير لا خطأ**. نسخة
rem  سطح المكتب تعمل بوضع محلي بلا سحابة، فبناءٌ بلا مفاتيح نتيجةٌ مشروعة
rem  للتجربة — لا فشلٌ يوقف الخطّ.
rem ============================================================================

set "ENV_FILE=%~dp0cloud.env"
if exist "%ENV_FILE%" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%ENV_FILE%") do (
    if not "%%A"=="" set "%%A=%%B"
  )
)

set DEFINES=
if "%1"=="--local" (
  echo [i] بناء محلي صريح: تُتجاهل أي أسرار سحابية.
) else (
  if not "%SUPABASE_URL%"=="" if not "%SUPABASE_ANON_KEY%"=="" (
    rem الأعلام يجب أن تطابق الخلفية التي كُتبت بها البيانات — مثل build_cloud.bat.
    if "%PHONE_IDENTITY%"=="" set PHONE_IDENTITY=1
    if "%COLD_FETCH%"==""     set COLD_FETCH=1
    set "DEFINES=--dart-define=SUPABASE_URL=!SUPABASE_URL! --dart-define=SUPABASE_ANON_KEY=!SUPABASE_ANON_KEY! --dart-define=R2_WORKER=!R2_WORKER! --dart-define=PHONE_IDENTITY=!PHONE_IDENTITY! --dart-define=COLD_FETCH=!COLD_FETCH!"
    echo [i] بناء موصول بالسحابة: حُقنت أسرار Supabase/R2.
  ) else (
    echo [!] لا أسرار سحابية ^(SUPABASE_URL/ANON_KEY^) — بناء بوضع محلي.
    echo     املأ tool\cloud.env لبناء موصول، أو مرّر --local لإسكات هذا.
  )
)

echo.
echo === [1/2] flutter build windows --release ===
flutter build windows --release %DEFINES%
if errorlevel 1 (
  echo [X] فشل بناء ويندوز.
  exit /b 1
)

echo.
echo === [2/2] dart run msix:create ===
rem التوقيع للنشر: اضبط certificate_path/password في msix_config بشهادة حقيقية،
rem أو استعمل شهادة self-signed للتجربة كما في WINDOWS_DEPLOY_AR.md. بلا شهادة
rem تُنتَج حزمة غير موقَّعة صالحة للفحص الداخلي فقط.
dart run msix:create
if errorlevel 1 (
  echo [X] فشل إنشاء MSIX.
  exit /b 1
)

echo.
echo [✓] تمّ. الناتج في:
echo     build\windows\x64\runner\Release\       ^(EXE + DLLs^)
echo     build\windows\x64\runner\Release\*.msix ^(الحزمة^)
exit /b 0
