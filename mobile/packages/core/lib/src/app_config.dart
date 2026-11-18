/// Which Event 360 app is running; sent to the API on device registration.
enum Event360App { user, organizer, crew }

class AppConfig {
  const AppConfig({required this.app, required this.apiBaseUrl});

  final Event360App app;
  final String apiBaseUrl;

  /// Values come from `--dart-define=API_BASE_URL=...` per flavor (dev/staging/prod).
  factory AppConfig.fromEnvironment(Event360App app) => AppConfig(
        app: app,
        apiBaseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:3000'),
      );
}
