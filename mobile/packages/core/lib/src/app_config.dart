/// Which Event 360 app is running; sent to the API on device registration.
enum Event360App { user, organizer, crew }

class AppConfig {
  const AppConfig({required this.app, required this.apiBaseUrl});

  final Event360App app;
  final String apiBaseUrl;

  /// From `--dart-define=API_BASE_URL=...`; defaults to the dev environment.
  factory AppConfig.fromEnvironment(Event360App app) => AppConfig(
        app: app,
        apiBaseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: 'https://api.dev.event360.corexlab.net'),
      );

  bool get isDev => apiBaseUrl.contains('.dev.');
}
