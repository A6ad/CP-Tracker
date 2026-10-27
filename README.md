# CP Tracker — Flutter Skeleton

Navigation flow implemented: Splash → Onboarding → Login/Register/Forgot
Password → Connect Codeforces → Dashboard (Home, Progress, Practice,
Contests, Profile tabs via bottom nav).

State management: Riverpod (`flutter_riverpod`). See `lib/providers/`.

## To run

Platform folders are already present, so it is a normal Flutter project:

```bash
flutter pub get
flutter run
```

The app talks to the FastAPI backend in `backend/`, which must be running and
reachable. Start it first (see `backend/README.md`), then point the app at it:

```bash
# Android emulator (default) reaches the host machine at 10.0.2.2
flutter run

# Physical device or desktop: use the host machine's LAN IP
flutter run --dart-define=API_BASE_URL=http://<your-lan-ip>:8000
```

`lib/services/api_config.dart` reads `API_BASE_URL` and defaults to
`http://10.0.2.2:8000`.

The address can also be changed at runtime from **Profile → Server**, from the
login screen, or from the “Can’t reach the server” screen. The saved value is
stored in `shared_preferences`, survives restarts, and overrides the build-time
default — useful when the laptop's DHCP address changes.

## What's wired up vs. placeholder

- All navigation between screens is real and working.
- Auth is fully wired to the backend: `lib/providers/auth_provider.dart` →
  `ApiClient` → `POST /auth/login|register|refresh`. JWTs are persisted via
  `shared_preferences` (`lib/services/token_store.dart`); a 401 triggers one
  transparent refresh-and-retry, and an unrecoverable session clears the
  tokens and falls back to logged out.
- Email ownership is verified before an account can link a Codeforces handle:
  1. Registration creates the account unverified and emails a 6-digit code.
     The default `EMAIL_BACKEND=console` logs the code instead of sending mail
     and echoes it to the app as `dev_verification_code` for local testing.
  2. The app blocks on `VerifyEmailScreen` (with resend) until the code is
     accepted by `POST /auth/verify-email`.
  3. `/user/link-codeforces/*` returns 403 until `email_verified` is true.
     Codes expire after 30 minutes and lock after 5 wrong attempts.
- Codeforces linking is a two-step ownership check:
  1. `POST /user/link-codeforces/start` validates the handle and returns a
     one-time code.
  2. The user pastes that code into their public Codeforces profile (First
     name, Last name, or Organization).
  3. `POST /user/link-codeforces/verify` re-reads the profile and links the
     handle only if the code is present. Codes expire after 30 minutes.
  This prevents someone from claiming a handle they do not own.
- These tabs fetch live data from the backend:
  - `home_tab.dart` — `GET /user/stats`, `GET /user/recent-submissions`
  - `progress_tab.dart` — `GET /stats/rating-history`, `GET /stats/by-rating`,
    `GET /stats/topics`
  - `practice_tab.dart` — `GET /practice/problems` (unsolved problems near the
    user's rating, built from the public Codeforces problemset; filters for
    recommended/unsolved/harder/random)
  - `contests_tab.dart` — `GET /contests` (upcoming and recently finished
    rounds from the public contest list)
  - `profile_tab.dart` — `GET /user/goals`, plus logout
- Problems and contests open on codeforces.com via `url_launcher`.
- The backend address is editable at runtime (`ServerSettingsScreen`), with a
  `/health` test button, persistent storage, and a reset to the default.
- Last successful responses are cached on-device (`shared_preferences`, see
  `lib/services/local_cache.dart`). If the backend is unreachable, the app opens
  straight to the dashboard with the saved profile and stats, and shows an
  amber "Offline · saved ..." banner with a Retry action. The cache is cleared
  on logout and whenever the server URL changes.
- All tabs have loading, error-with-retry, and empty states.

## Next steps

- Real password reset (`forgot_password_screen.dart` is still UI-only).
- Rate-limit login and support refresh-token revocation.
