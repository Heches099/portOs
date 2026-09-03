@echo off
setlocal EnableExtensions DisableDelayedExpansion

if not exist ".env.local" (
  echo Missing .env.local. Copy .env.local.example to .env.local and fill in your Firebase web app values.
  exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%A in (".env.local") do (
  if not "%%A"=="" set "%%A=%%B"
)

for %%V in (FIREBASE_API_KEY FIREBASE_PROJECT_ID FIREBASE_MESSAGING_SENDER_ID FIREBASE_WEB_APP_ID FIREBASE_AUTH_DOMAIN FIREBASE_STORAGE_BUCKET) do (
  if not defined %%V (
    echo Missing required environment variable: %%V
    exit /b 1
  )
)

where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter was not found on PATH.
  exit /b 1
)

flutter run -d chrome ^
  --dart-define=FIREBASE_API_KEY="%FIREBASE_API_KEY%" ^
  --dart-define=FIREBASE_PROJECT_ID="%FIREBASE_PROJECT_ID%" ^
  --dart-define=FIREBASE_MESSAGING_SENDER_ID="%FIREBASE_MESSAGING_SENDER_ID%" ^
  --dart-define=FIREBASE_WEB_APP_ID="%FIREBASE_WEB_APP_ID%" ^
  --dart-define=FIREBASE_AUTH_DOMAIN="%FIREBASE_AUTH_DOMAIN%" ^
  --dart-define=FIREBASE_STORAGE_BUCKET="%FIREBASE_STORAGE_BUCKET%" ^
  --dart-define=PORT_API_BASE_URL="%PORT_API_BASE_URL%" %*
