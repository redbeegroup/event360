import 'package:cached_network_image/cached_network_image.dart';
import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/event_card.dart';

/// Public organizer page: logo, about, links/contact (if shared) and their upcoming events.
class OrganizerScreen extends ConsumerWidget {
  const OrganizerScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final org = ref.watch(organizerProvider(slug));

    return Scaffold(
      appBar: AppBar(title: Text(t.organizer)),
      body: org.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => MessageView(icon: Icons.wifi_off, message: t.loadError, actionLabel: t.retry, onAction: () => ref.invalidate(organizerProvider(slug))),
        data: (o) {
          final about = pickLang(lang, o.description, o.descriptionMy);
          Widget link(IconData icon, String label, Uri uri) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon),
                title: Text(label),
                onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
              );
          return ListView(padding: const EdgeInsets.all(20), children: [
            Row(children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                backgroundImage: o.logoUrl == null ? null : CachedNetworkImageProvider(o.logoUrl!),
                child: o.logoUrl == null ? Text(o.name.characters.first.toUpperCase(), style: theme.textTheme.headlineSmall) : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.name, style: theme.textTheme.headlineSmall),
                  if (o.verified)
                    Row(children: [
                      Icon(Icons.verified, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(t.verified, style: theme.textTheme.bodySmall),
                    ]),
                ]),
              ),
            ]),
            if (about.isNotEmpty) ...[const SizedBox(height: 16), Text(about, style: theme.textTheme.bodyLarge)],
            const SizedBox(height: 8),
            if (o.website != null) link(Icons.language, t.website, Uri.parse(o.website!)),
            if (o.facebookUrl != null) link(Icons.facebook, t.facebook, Uri.parse(o.facebookUrl!)),
            if (o.contactPhone != null && o.contactPhone!.isNotEmpty) link(Icons.phone, o.contactPhone!, Uri(scheme: 'tel', path: o.contactPhone)),
            if (o.contactEmail != null && o.contactEmail!.isNotEmpty) link(Icons.email_outlined, o.contactEmail!, Uri(scheme: 'mailto', path: o.contactEmail)),
            const SizedBox(height: 12),
            Text(t.organizerEvents, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (o.events.isEmpty) MessageView(icon: Icons.event_busy, message: t.noUpcomingEvents),
            for (final e in o.events) Padding(padding: const EdgeInsets.only(bottom: 12), child: EventCard(event: e)),
          ]);
        },
      ),
    );
  }
}
