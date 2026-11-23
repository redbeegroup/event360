import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

Widget loadError(L10n t, VoidCallback retry) => MessageView(icon: Icons.wifi_off, message: t.loadError, actionLabel: t.retry, onAction: retry);

Widget readOnly(BuildContext context, L10n t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [const Icon(Icons.lock_outline, size: 18), const SizedBox(width: 6), Expanded(child: Text(t.readOnly, style: Theme.of(context).textTheme.bodySmall))]),
    );

/// Scroll behaviour that also drags with a mouse (web and desktop), for the sideways rows.
const dragEverywhere = _DragEverywhere();

class _DragEverywhere extends MaterialScrollBehavior {
  const _DragEverywhere();
  @override
  Set<PointerDeviceKind> get dragDevices => {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.stylus, PointerDeviceKind.trackpad};
}

/// A row that scrolls sideways, with room after the last item and a fade at the right edge while there is more.
class FadingHScroll extends StatefulWidget {
  const FadingHScroll({super.key, required this.child, this.fadeKey, this.padding = EdgeInsets.zero});
  final Widget child;
  final Key? fadeKey;
  final EdgeInsets padding;
  @override
  State<FadingHScroll> createState() => _FadingHScrollState();
}

class _FadingHScrollState extends State<FadingHScroll> {
  final _scroll = ScrollController();
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_measure);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _measure() {
    if (!_scroll.hasClients) return;
    final more = _scroll.position.maxScrollExtent - _scroll.offset > 1;
    if (more != _more) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Stack(children: [
      ScrollConfiguration(
        behavior: dragEverywhere,
        child: SingleChildScrollView(controller: _scroll, scrollDirection: Axis.horizontal, padding: widget.padding, child: widget.child),
      ),
      Positioned(
        top: 0,
        bottom: 0,
        right: 0,
        width: 32,
        child: IgnorePointer(
          child: AnimatedOpacity(
            key: widget.fadeKey,
            opacity: _more ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [bg.withValues(alpha: 0), bg]))),
          ),
        ),
      ),
    ]);
  }
}
