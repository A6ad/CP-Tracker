/// Thrown for any non-successful API interaction.
///
/// [message] is safe to show to the user; [statusCode] is null for
/// network-level failures (timeouts, no connection).
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// A display-safe message for an error surfaced to the UI.
///
/// [ApiException]s already carry a user-facing message; anything else is
/// unexpected, so hide the raw exception text behind a generic line.
String errorMessage(Object error) =>
    error is ApiException ? error.message : 'Something went wrong.';

