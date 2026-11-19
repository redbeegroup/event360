import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';

/// Live camera QR scanner. Calls [onCode] with each decoded QR text (the caller ignores repeats).
class QrScannerView extends ConsumerStatefulWidget {
  const QrScannerView({super.key, required this.onCode, this.paused = false});
  final ValueChanged<String> onCode;
  final bool paused;

  @override
  ConsumerState<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends ConsumerState<QrScannerView> {
  MobileScannerController? _controller;

  @override
  void initState() {
    super.initState();
    if (ref.read(cameraEnabledProvider)) {
      _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.normal);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final c = _controller;
    if (c == null) return _Placeholder(text: t.cameraUnavailable);
    return Stack(fit: StackFit.expand, children: [
      MobileScanner(
        controller: c,
        onDetect: (capture) {
          if (widget.paused) return;
          for (final b in capture.barcodes) {
            final v = b.rawValue;
            if (v != null && v.isNotEmpty) {
              widget.onCode(v);
              break;
            }
          }
        },
        errorBuilder: (context, error) => _Placeholder(text: t.cameraUnavailable),
      ),
      // Aiming frame (hidden when the camera failed, so it doesn't cover the message)
      ValueListenableBuilder<MobileScannerState>(
        valueListenable: c,
        builder: (_, st, __) => st.error != null
            ? const SizedBox.shrink()
            : IgnorePointer(
                child: Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
      ),
    ]);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black87,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
        ]),
      );
}
