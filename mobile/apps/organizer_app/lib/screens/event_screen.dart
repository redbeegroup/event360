import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import 'event/announce_tab.dart';
import 'event/door_tab.dart';
import 'event/overview_tab.dart';
import 'event/promos_tab.dart';

export 'event/overview_tab.dart' show StatTile, orderStatusLabel;

/// One event: live overview, door codes, announcements and promo codes.
class EventScreen extends ConsumerWidget {
  const EventScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final org = ref.watch(currentOrgProvider);
    final event = ref.watch(orgEventsProvider).value?.where((e) => e.id == eventId).firstOrNull;
    if (org == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final k = (orgId: org.id, eventId: eventId);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(event == null ? '' : pickLang(lang, event.title, event.titleMy), maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(key: const Key('tabOverview'), text: t.tabOverview),
            Tab(key: const Key('tabDoor'), text: t.tabDoor),
            Tab(key: const Key('tabAnnounce'), text: t.tabAnnounce),
            Tab(key: const Key('tabPromos'), text: t.tabPromos),
          ]),
        ),
        body: TabBarView(children: [
          OverviewTab(k: k),
          DoorTab(k: k, canEdit: org.canEdit),
          AnnounceTab(k: k, canEdit: org.canEdit),
          PromosTab(k: k, canEdit: org.canEdit),
        ]),
      ),
    );
  }
}
