@echo off
setlocal enabledelayedexpansion
rem ============================================================================
rem بناء موصول بالسحابة (Supabase + R2) — انظر tool/build_cloud.sh للتفاصيل
rem الاستخدام: tool\build_cloud.bat [trial^|debug^|release^|windows] ^<رقم_البناء^>
rem
rem م68/دفعة ثان-أ — أُخرجت الأسرار من هذا الملف. القيم تُقرأ من
rem tool\cloud.env (مستثنى من git — انسخ tool\cloud.env.example واملأه)،
rem أو من متغيّرات البيئة إن كانت مضبوطة سلفاً (مناسب لـ CI).
rem
rem تذكير: المفتاح الذي كان مكتوباً هنا سابقاً يجب اعتباره مكشوفاً — دوّره
rem من لوحة Supabase؛ إزالته من الملف وحدها لا تُبطله.
rem ============================================================================

set "ENV_FILE=%~dp0cloud.env"
if exist "%ENV_FILE%" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%ENV_FILE%") do (
    if not "%%A"=="" set "%%A=%%B"
  )
)

if "%SUPABASE_URL%"=="" goto :missing
if "%SUPABASE_ANON_KEY%"=="" goto :missing

set MODE=%1
if "%MODE%"=="" set MODE=trial

rem رقم البناء: لا افتراض له عمداً — الافتراض السابق (48) كان أقدم من
rem المنشور (v62)، فينتج versionCode أقدم ويرفض أندرويد التثبيت.
set BUILD_NUM=%2
if "%BUILD_NUM%"=="" (
  echo [X] مرر رقم البناء: %0 %MODE% ^<رقم_البناء^>
  exit /b 1
)

if "%PHONE_IDENTITY%"=="" set PHONE_IDENTITY=1
if "%COLD_FETCH%"==""     set COLD_FETCH=1

set VER=--build-number=%BUILD_NUM% --build-name=1.0.%BUILD_NUM%
set DEFINES=--dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY% --dart-define=R2_WORKER=%R2_WORKER% --dart-define=PHONE_IDENTITY=%PHONE_IDENTITY% --dart-define=COLD_FETCH=%COLD_FETCH%
set OBFUSCATE=--obfuscate --split-debug-info=build/symbols

if "%MODE%"=="trial" (
  set ORG_GRADLE_PROJECT_trialSuffix=true
  flutter build apk --release --split-per-abi %VER% %DEFINES% %OBFUSCATE%
) else if "%MODE%"=="debug" (
  flutter build apk --debug --split-per-abi %VER% %DEFINES%
) else if "%MODE%"=="release" (
  flutter build apk --release --split-per-abi %VER% %DEFINES% %OBFUSCATE%
) else if "%MODE%"=="windows" (
  flutter build windows %VER% %DEFINES%
)
exit /b %ERRORLEVEL%

:missing
echo [X] قيم سحابية ناقصة: SUPABASE_URL / SUPABASE_ANON_KEY
echo     انسخ tool\cloud.env.example الى tool\cloud.env واملاه
echo     ^(الملف مستثنى من git عمدا - لا تضفه^)
exit /b 1
