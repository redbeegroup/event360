import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';

void main() {
  final config = AppConfig.fromEnvironment(Event360App.organizer);
  runApp(App(api: Event360Api(config, SecureTokenStore())));
}

class App extends StatelessWidget {
  const App({super.key, required this.api});

  final Event360Api api;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Event 360 Organizer',
        theme: Event360Theme.light(),
        darkTheme: Event360Theme.dark(),
        home: HomeScreen(api: api),
      );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.api});

  final Event360Api api;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Event 360 Organizer')),
        body: FutureBuilder<List<Category>>(
          future: api.categories(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Cannot reach API: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            return ListView(
              children: [
                for (final c in snap.data!)
                  ExpansionTile(
                    title: Text(c.name('en')),
                    children: [for (final s in c.children) ListTile(title: Text(s.name('en')))],
                  ),
              ],
            );
          },
        ),
      );
}
