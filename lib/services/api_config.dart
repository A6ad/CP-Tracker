/// Backend endpoint contract for CP Tracker.
///
/// The FastAPI service in `backend/` implements these routes.
///
/// - `POST /auth/login`    { email, password }           -> TokenResponse
/// - `POST /auth/register` { email, password }           -> TokenResponse
/// - `POST /auth/refresh`  { refresh_token }             -> TokenResponse
/// - `POST /auth/verify-email` { email, code }           -> UserResponse
/// - `POST /auth/resend-verification` { email }          -> ResendResponse
/// - `GET  /user/me`                                     -> UserResponse
/// - `POST /user/link-codeforces/start`  { handle }      -> LinkStartResponse
/// - `POST /user/link-codeforces/verify` { code }        -> UserResponse
/// - `GET  /practice/problems?mode=...`                  -> PracticeResponse
/// - `GET  /contests`                                    -> ContestsResponse
///
/// All authenticated routes expect `Authorization: Bearer <access_token>`.
class ApiConfig {
  /// Override at build/run time:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
  ///
  /// Users can also change this at runtime from Profile → Server; the saved
  /// value takes precedence and needs no rebuild.
  ///
  /// Default is the Android emulator loopback to the host machine.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Kept short enough that an unreachable backend falls back to saved data
  /// quickly; the local backend normally answers in well under a second.
  static const Duration timeout = Duration(seconds: 8);
}
