# PortOS NextGen

Flutter command-center dashboard with:

- Firebase Auth sign-in
- Firestore-backed live terminal and operations data
- Presentation-mode fallback data when Firebase is not configured
- FastAPI backend support for admin APIs and ingest workflows

## Run In Presentation Mode

```bash
flutter run -d chrome
```

If Firebase config is missing, the app stays fully usable with seeded presentation data.

## Run Against Real Firebase

The app can initialize Firebase from `--dart-define` values, so you can test real Auth and Firestore without committing platform config files.

## Firebase CLI Bootstrap

For local setup you only need the Firebase CLI. `gcloud` is optional unless you want to manage Google Cloud services from the terminal.

Common package names on Debian or Kali:

- `ripgrep` provides the `rg` command
- `google-cloud-cli` provides the `gcloud` command after adding the Google Cloud apt repo

Quick checks:

```bash
firebase --version
firebase login
firebase projects:list | grep "$PROJECT_ID"
```

If you prefer `rg`, install it first:

```bash
sudo apt update
sudo apt install ripgrep
```

If you want `gcloud`, use the official Google Cloud apt repo, then install `google-cloud-cli`.

## Firestore Setup Notes

Create the default Firestore database with:

```bash
firebase firestore:databases:create '(default)' \
  --location="$FIRESTORE_LOCATION" \
  --project "$PROJECT_ID"
```

If the command fails with `Cloud Firestore API has not been used in project ... before or it is disabled`, enable the API first in Google Cloud, then retry:

```text
https://console.developers.google.com/apis/api/firestore.googleapis.com/overview?project=$PROJECT_ID
```

If the CLI fails with `Failed to make request`, `EAI_AGAIN`, or other intermittent fetch errors, the issue is usually local DNS or network instability rather than Firebase configuration. In that case:

1. Retry the command after a minute.
2. Enable the API in the console first, then retry database creation.
3. Use Firebase Console or Cloud Shell if your local machine keeps dropping requests to `*.googleapis.com`.

## Local Firebase Launch

Copy the example file first, then fill in your Firebase web app values locally:

```bash
cp .env.local.example .env.local
```

After that, the quickest real-Firebase run path is:

```bash
./run_web_firebase.sh
```

That command loads values from `.env.local` and passes them through `--dart-define` values without committing them.

Shared values:

- `FIREBASE_API_KEY`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_STORAGE_BUCKET` optional
- `FIREBASE_AUTH_DOMAIN` optional, web only
- `FIREBASE_MEASUREMENT_ID` optional
- `FIREBASE_DATABASE_URL` optional

Platform app ids:

- `FIREBASE_WEB_APP_ID`
- `FIREBASE_ANDROID_APP_ID`
- `FIREBASE_IOS_APP_ID`
- `FIREBASE_MACOS_APP_ID`

Example for Chrome:

```bash
flutter run -d chrome \
  --dart-define=FIREBASE_API_KEY=your-api-key \
  --dart-define=FIREBASE_PROJECT_ID=your-project-id \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=your-sender-id \
  --dart-define=FIREBASE_WEB_APP_ID=your-web-app-id \
  --dart-define=FIREBASE_AUTH_DOMAIN=your-project-id.firebaseapp.com \
  --dart-define=FIREBASE_STORAGE_BUCKET=your-project-id.firebasestorage.app
```

## Firestore Collections

When Firestore is enabled and the database is empty, the app seeds test data into these collections:

- `terminal_stats/current`
- `agvs`
- `cranes`
- `deliveries`
- `camera_feeds`
- `sensor_readings`

This lets you sign in and test the real data path immediately.

## Auth And Rules

For the current Spark no-cost setup:

1. Enable Email/Password in Firebase Authentication.
2. Create operator accounts manually in Firebase Authentication.
3. Sign in from the Flutter web app with that email and password.

The included `firestore.rules` and `storage.rules` allow any authenticated Firebase user to use the app's current realtime data path.

If you later add custom claims or the FastAPI backend admin routes, you can tighten these rules back down to admin-only access.

## Android Note

If you test on Android, the package id must match the Android app registered in your Firebase project. You can override it without editing code:

```bash
PORTOS_APPLICATION_ID=com.yourcompany.portos flutter run -d android
```

## Backend

The FastAPI backend setup and Firebase Admin configuration are documented in [BACKED_SETUP.md](/home/harris/dofu/tech/BACKED_SETUP.md).
