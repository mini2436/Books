# Mobile Shell

The mobile client uses Capacitor to wrap the shared web reader.

## Planned responsibilities

- Persist auth state securely on device
- Provide local SQLite storage for offline sync
- Detect connectivity changes and trigger sync retries
- Support future offline download and local notifications

## Development flow

1. Build the web app.
2. Point Capacitor to the web build output or a local dev server.
3. Run `npx cap sync`.
4. Open Android Studio or Xcode through Capacitor.

