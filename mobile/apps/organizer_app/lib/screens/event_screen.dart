import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import 'event/announce_tab.dart';
import 'event/door_tab.dart';
import 'event/guests_tab.dart';
import 'event/overview_tab.dart';
import 'event/promos_tab.dart';
import 'event/sales_tab.dart';
import 'event/seats_tab.dart';

export 'event/overview_tab.dart' show StatTile, orderStatusLabel;

/// One event: live overview, guests, seats (only with a seat map), sales, door codes, announcements and promo codes.
class EventScreen extends ConsumerStatefulWidget {
  const EventScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends ConsumerState<EventScreen> with TickerProviderStateMixin {
  TabController? _tabs;
  List<String> _ids = const [];
  // Replaced controllers wait here until the frame is done; disposed with the screen at the latest.
  final _retired = <TabController>[];

  @override
  void dispose() {
    _tabs?.dispose();
    for (final c in _retired) {
      c.dispose();
    }
    _retired.clear();
    super.dispose();
  }

  /// The Seats tab appears once the seating data says there is a map. The controller is replaced then,
  /// landing on the same tab as before, so the open tab is not reset.
  TabController _controllerFor(List<String> ids) {
    final old = _tabs;
    if (old != null && _ids.length == ids.length) return old;
    final current = old == null ? null : _ids[old.index];
    final index = current == null ? 0 : ids.indexOf(current).clamp(0, ids.length - 1);
    final next = TabController(length: ids.length, vsync: this, initialIndex: index);
    _tabs = next;
    _ids = ids;
    if (old != null) {
      _retired.add(old);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_retired.remove(old)) old.dispose();
      });
    }
    return next;
  }

  void _openSales() {
    final c = _tabs;
    final i = _ids.indexOf('sales');
    if (c != null && i >= 0) c.animateTo(i);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final org = ref.watch(currentOrgProvider);
    final eventId = widget.eventId;
    final event = ref.watch(orgEventsProvider).value?.where((e) => e.id == eventId).firstOrNull;
    if (org == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final k = (orgId: org.id, eventId: eventId);
    // A failed fetch keeps the tab (with a retry) rather than hiding it on an event that has a map.
    final seating = ref.watch(orgSeatingProvider(k));
    final hasSeats = seating.hasValue ? seating.value!.hasMap : seating.hasError;
    final ids = ['overview', 'guests', if (hasSeats) 'seats', 'sales', 'door', 'announce', 'promos'];
    final controller = _controllerFor(ids);
    return Scaffold(
      appBar: AppBar(
        title: Text(event == null ? '' : pickLang(lang, event.title, event.titleMy), maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: TabBar(controller: controller, isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
          Tab(key: const Key('tabOverview'), text: t.tabOverview),
          Tab(key: const Key('tabGuests'), text: t.tabGuests),
          if (hasSeats) Tab(key: const Key('tabSeats'), text: t.tabSeats),
          Tab(key: const Key('tabSales'), text: t.tabSales),
          Tab(key: const Key('tabDoor'), text: t.tabDoor),
          Tab(key: const Key('tabAnnounce'), text: t.tabAnnounce),
          Tab(key: const Key('tabPromos'), text: t.tabPromos),
        ]),
      ),
      body: TabBarView(controller: controller, children: [
        OverviewTab(k: k, onAllOrders: _openSales),
        GuestsTab(k: k, canEdit: org.canEdit, event: event),
        if (hasSeats) SeatsTab(k: k, canEdit: org.canEdit),
        SalesTab(k: k),
        DoorTab(k: k, canEdit: org.canEdit),
        AnnounceTab(k: k, canEdit: org.canEdit),
        PromosTab(k: k, canEdit: org.canEdit),
      ]),
    );
  }
}
