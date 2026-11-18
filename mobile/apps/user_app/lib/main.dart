import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';

void main() {
  final config = AppConfig.fromEnvironment(Event360App.user);
  runApp(App(api: Event360Api(config)));
}

class App extends StatelessWidget {
  const App({super.key, required this.api});

  final Event360Api api;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Event 360',
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
        appBar: AppBar(title: const Text('Event 360')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: api.categories(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Cannot reach API: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            return ListView(
              children: [
                for (final c in snap.data!)
                  ExpansionTile(
                    title: Text(c['nameEn'] as String),
                    children: [
                      for (final s in (c['children'] as List).cast<Map<String, dynamic>>())
                        ListTile(title: Text(s['nameEn'] as String)),
                    ],
                  ),
              ],
            );
          },
        ),
      );
}
