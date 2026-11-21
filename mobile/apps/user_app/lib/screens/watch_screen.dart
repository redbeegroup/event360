import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';

/// Builds the actual video view. Overridden in widget tests (no video plugin there).
typedef PlayerViewBuilder = Widget Function({required String url, required bool live, required String resumeKey, required VoidCallback onEnded});

final playerViewProvider = Provider<PlayerViewBuilder>(
  (ref) => ({required url, required live, required resumeKey, required onEnded}) =>
      HlsPlayer(url: url, live: live, resumeKey: resumeKey, onEnded: onEnded),
);

/// Plays a live stream ('live', channel id) or a recording ('vod', recording id) for ticket holders.
/// Keeps the playback session alive (heartbeat) and stops when another device takes over.
class WatchScreen extends ConsumerStatefulWidget {
  const WatchScreen({super.key, required this.kind, required this.id, required this.title});
  final String kind;
  final String id;
  final String title;

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  WatchGrant? _grant;
  String? _error;
  bool _ended = false;
  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _start() async {
    final me = await ref.read(sessionProvider.future);
    if (!mounted) return;
    if (me == null) {
      final here = '/watch/${widget.kind}/${widget.id}?title=${Uri.encodeQueryComponent(widget.title)}';
      context.pushReplacement('/login?from=${Uri.encodeComponent(here)}');
      return;
    }
    try {
      final g = await ref.read(apiProvider).watchToken(widget.kind, widget.id);
      if (!mounted) return;
      setState(() => _grant = g);
      _heartbeat = Timer.periodic(Duration(seconds: g.heartbeatSeconds), (_) => _beat());
    } on ApiException catch (e) {
      if (!mounted) return;
      final t = L10n.of(context);
      setState(() => _error = switch (e.status) {
            403 => t.needTicketToWatch,
            410 => t.notLiveNow,
            _ => t.videoError,
          });
    }
  }

  Future<void> _beat() async {
    final g = _grant;
    if (g == null) return;
    try {
      await ref.read(apiProvider).watchHeartbeat(g.sessionId);
    } on ApiException catch (e) {
      if (e.status == 409 && mounted) {
        _heartbeat?.cancel();
        setState(() {
          _grant = null;
          _error = L10n.of(context).otherDevice;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final g = _grant;
    final live = widget.kind == 'live';
    return Scaffold(
      backgroundColor: E360Colors.night,
      appBar: AppBar(
        backgroundColor: E360Colors.night,
        foregroundColor: Colors.white,
        shape: const Border(bottom: BorderSide(color: Color(0x33FFFFFF))),
        titleTextStyle: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
        title: Row(children: [
          if (live)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: E360Colors.danger, borderRadius: BorderRadius.circular(6)),
              child: Text(t.liveNow, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, key: const Key('watchError'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),
              )
            : _ended
                ? Padding(padding: const EdgeInsets.all(24), child: Text(t.liveEnded, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)))
                : g == null
                    ? const CircularProgressIndicator()
                    : Stack(children: [
                        ref.watch(playerViewProvider)(
                          url: g.url,
                          live: live,
                          resumeKey: 'vod_pos_${widget.id}',
                          onEnded: () {
                            if (live && mounted) setState(() => _ended = true);
                          },
                        ),
                        // Visible watermark (discourages screen recording)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: IgnorePointer(
                            child: Text(g.watermark, key: const Key('watermark'), style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                          ),
                        ),
                      ]),
      ),
    );
  }
}

/// HLS player on top of video_player (ExoPlayer / AVPlayer / hls.js on the web). Quality adapts automatically.
class HlsPlayer extends ConsumerStatefulWidget {
  const HlsPlayer({super.key, required this.url, required this.live, required this.resumeKey, required this.onEnded});
  final String url;
  final bool live;
  final String resumeKey;
  final VoidCallback onEnded;

  @override
  ConsumerState<HlsPlayer> createState() => _HlsPlayerState();
}

class _HlsPlayerState extends ConsumerState<HlsPlayer> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url), formatHint: VideoFormat.hls);
  bool _ready = false;
  bool _failed = false;
  bool _showControls = true;
  bool _full = false;
  Timer? _save;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
    _c.initialize().then((_) async {
      if (!mounted) return;
      final saved = ref.read(prefsProvider).getInt(widget.resumeKey);
      if (!widget.live && saved != null && saved > 5 && saved < _c.value.duration.inSeconds - 10) {
        await _c.seekTo(Duration(seconds: saved));
      }
      await _c.play();
      setState(() => _ready = true);
      if (!widget.live) {
        _save = Timer.periodic(const Duration(seconds: 5), (_) => ref.read(prefsProvider).setInt(widget.resumeKey, _c.value.position.inSeconds));
      }
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  void _onTick() {
    final v = _c.value;
    if (v.isInitialized && !v.isPlaying && v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 500)) {
      widget.onEnded();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _save?.cancel();
    _c.removeListener(_onTick);
    _c.dispose();
    super.dispose();
  }

  void _toggleFull() {
    setState(() => _full = !_full);
    if (_full) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations(const []);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return '${h > 0 ? '$h:' : ''}${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Padding(padding: const EdgeInsets.all(24), child: Text(L10n.of(context).videoError, style: const TextStyle(color: Colors.white70)));
    }
    if (!_ready) return const CircularProgressIndicator();
    final v = _c.value;
    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: AspectRatio(
        aspectRatio: v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio,
        child: Stack(fit: StackFit.expand, children: [
          VideoPlayer(_c),
          if (v.isBuffering) const Center(child: CircularProgressIndicator()),
          if (_showControls)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black45,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(children: [
                  IconButton(
                    color: Colors.white,
                    icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: () => v.isPlaying ? _c.pause() : _c.play(),
                  ),
                  if (widget.live)
                    const Expanded(child: Text('●  LIVE', style: TextStyle(color: Color(0xFFFF5252), fontWeight: FontWeight.w700)))
                  else ...[
                    Text(_fmt(v.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: VideoProgressIndicator(_c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: Colors.white)),
                      ),
                    ),
                    Text(_fmt(v.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                  IconButton(color: Colors.white, icon: Icon(_full ? Icons.fullscreen_exit : Icons.fullscreen), onPressed: _toggleFull),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
