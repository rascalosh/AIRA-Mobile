/// Build-time configuration passed with `--dart-define`.
///
/// No API credentials are ever embedded in the app: the mobile client only
/// talks to the image-processing backend, which holds all ML service secrets.
class AppConfig {
  AppConfig._();

  /// Image-processing API base URL. `10.0.2.2` is the host machine from the
  /// Android emulator; use HTTPS for any non-local deployment.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(minutes: 5);
  static const Duration sendTimeout = Duration(minutes: 10);
}
