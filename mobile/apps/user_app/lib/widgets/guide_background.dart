import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/guide_providers.dart';

/// Sits in the app shell: starts the background saver (so it runs whichever tab the buyer lands on) and refreshes "Happening today" when
/// the app comes back to the foreground. Draws nothing of its own.
class GuideBackground extends ConsumerStatefulWidget {
  const GuideBackground({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<GuideBackground> createState() => _GuideBackgroundState();
}

class _GuideBackgroundState extends ConsumerState<GuideBackground> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(todayEventsProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(eventSaverProvider);
    return widget.child;
  }
}
