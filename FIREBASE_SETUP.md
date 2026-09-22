# Firebase Setup

The app now reads and writes competitors, divisions, and tatami assignments from Cloud Firestore.

Before it can connect to your Firebase project, you need to replace the placeholder configuration in `lib/firebase_options.dart` with real Firebase values.

Recommended setup:

1. Install the FlutterFire CLI.
2. Run `flutterfire configure` from the project root.
3. Choose your Firebase project.
4. Select the platforms you want to support, including Windows if you plan to keep using the desktop app.
5. Let the CLI generate `lib/firebase_options.dart`.

After that, restart the app. The home screen warning banner will disappear and the app will start syncing with Firestore.

Collections used by the app:

- `competitors`
- `divisions`
- `tatamiAssignments`

Suggested Firestore rules for early development:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

Do not keep those open rules in production.