import 'dart:async';

import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/event_card.dart';

const _cities = ['Yangon', 'Mandalay', 'Naypyidaw', 'Bago', 'Mawlamyine', 'Taunggyi'];

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key, this.initialCategory});
  final String? initialCategory;
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  late SearchQuery _query = SearchQuery(category: widget.initialCategory);
  final _text = TextEditingController();
  Timer? _debounce;

  @override
  void didUpdateWidget(covariant ExploreScreen old) {
    super.didUpdateWidget(old);
    if (widget.initialCategory != old.initialCategory && widget.initialCategory != null) {
      setState(() => _query = _query.copyWith(category: widget.initialCategory));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onText(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _query = _query.copyWith(q: v)));
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final cats = ref.watch(categoriesProvider).value ?? const [];
    final results = ref.watch(searchResultsProvider(_query));

    return Scaffold(
      appBar: AppBar(title: Text(t.explore)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _text,
            onChanged: _onText,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t.searchHint),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            FilterChip(
              label: Text(t.freeOnly),
              selected: _query.freeOnly,
              onSelected: (v) => setState(() => _query = _query.copyWith(freeOnly: v)),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String?>(
              onSelected: (c) => setState(() => _query = c == null ? _query.copyWith(clearCity: true) : _query.copyWith(city: c)),
              itemBuilder: (_) => [
                PopupMenuItem(value: null, child: Text(t.anyCity)),
                for (final c in _cities) PopupMenuItem(value: c, child: Text(c)),
              ],
              child: Chip(avatar: const Icon(Icons.place_outlined, size: 18), label: Text(_query.city ?? t.city)),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(t.allCategories),
              selected: _query.category == null,
              onSelected: (_) => setState(() => _query = _query.copyWith(clearCategory: true)),
            ),
            for (final c in cats) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(c.name(lang)),
                selected: _query.category == c.slug,
                onSelected: (_) => setState(() => _query = _query.copyWith(category: c.slug)),
              ),
            ],
          ]),
        ),
        Expanded(
          child: results.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => MessageView(
              icon: Icons.wifi_off,
              message: t.loadError,
              actionLabel: t.retry,
              onAction: () => ref.invalidate(searchResultsProvider(_query)),
            ),
            data: (page) => page.items.isEmpty
                ? MessageView(icon: Icons.search_off, message: t.noEvents)
                : RefreshIndicator(
                    onRefresh: () => ref.refresh(searchResultsProvider(_query).future),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: page.items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => EventCard(event: page.items[i]),
                    ),
                  ),
          ),
        ),
      ]),
    );
  }
}
