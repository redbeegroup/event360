import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/lang_button.dart';

/// Crew accounts pick which event they're working.
class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final events = ref.watch(crewEventsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.chooseEvent), actions: [
        const LangButton(),
        IconButton(tooltip: t.signOut, icon: const Icon(Icons.logout), onPressed: () => ref.read(sessionProvider.notifier).signOut()),
      ]),
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t.loadError),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => ref.invalidate(crewEventsProvider), child: Text(t.retry)),
          ]),
        ),
        data: (list) => list.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t.noEvents, textAlign: TextAlign.center)))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(crewEventsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final e = list[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.event),
                        title: Text(pickLang(lang, e.title, e.titleMy), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([formatDayTime(e.startsAt, lang), if (e.venueName != null) e.venueName!].join(' · ')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => ref.read(sessionProvider.notifier).chooseEvent(e),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
