import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Independent low-rate stream: FFT frames never rebuild the main telemetry
/// snapshot or retain raw audio. One subscription per engine, regardless of how
/// many music widgets are visible; Android shares the capture across engines.
class AudioSpectrumService extends ChangeNotifier {
  static final shared = AudioSpectrumService();
  final MethodChannel methods;
  final EventChannel events;
  AudioSpectrumService(
      {this.methods =
          const MethodChannel('xyz.i4o.uni.launcher/spectrum-control'),
      this.events = const EventChannel('xyz.i4o.uni.launcher/spectrum')});
  final Set<Object> _owners = {};
  StreamSubscription<dynamic>? _subscription;
  List<double> levels = const [];
  bool granted = false, available = false;
  String status = 'idle';
  int sequence = 0;
  double peakLevel = 0;
  bool _disposed = false;
  int get activeConsumers => _owners.length;
  Future<void> refreshStatus() async {
    try {
      final packet = await methods.invokeMapMethod<String, dynamic>('status');
      if (!_disposed && packet != null) accept(packet);
    } catch (_) {
      if (!_disposed) accept({'status': 'unavailable', 'granted': false});
    }
  }

  void accept(Map packet) {
    if (_disposed) return;
    granted = packet['granted'] == true;
    available = packet['available'] == true;
    status = '${packet['status'] ?? 'unavailable'}';
    sequence = (packet['sequence'] as num?)?.toInt() ?? sequence;
    final raw = packet['levels'];
    levels = raw is List
        ? raw
            .take(24)
            .map((v) =>
                v is num && v.isFinite ? v.toDouble().clamp(0.0, 1.0) : 0.0)
            .toList(growable: false)
        : available
            ? levels
            : const [];
    // The native side reports the loudest band of the frame. Older packets
    // carry no peak, so the bands themselves are the fallback.
    final peak = packet['peakLevel'];
    peakLevel = peak is num && peak.isFinite
        ? peak.toDouble().clamp(0.0, 1.0)
        : levels.isEmpty
            ? 0
            : levels.reduce((a, b) => a > b ? a : b);
    notifyListeners();
  }

  void setDemand(Object owner, bool enabled) {
    if (_disposed) return;
    final wasActive = _owners.isNotEmpty;
    if (enabled) {
      _owners.add(owner);
    } else {
      _owners.remove(owner);
    }
    final active = _owners.isNotEmpty;
    if (wasActive == active) return;
    if (active) {
      _subscription = events.receiveBroadcastStream().listen((packet) {
        if (packet is Map && _owners.isNotEmpty) accept(packet);
      }, onError: (_) {
        accept({'status': 'unavailable', 'granted': granted});
      });
    }
    unawaited(
        methods.invokeMethod<void>('active', active).catchError((Object _) {}));
    if (!active) {
      unawaited(_subscription?.cancel());
      _subscription = null;
      levels = const [];
      available = false;
      status = 'idle';
      notifyListeners();
    }
  }

  Future<void> requestPermission() async {
    try {
      await methods.invokeMethod<void>('permission');
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _owners.clear();
    unawaited(_subscription?.cancel());
    unawaited(
        methods.invokeMethod<void>('active', false).catchError((Object _) {}));
    super.dispose();
  }
}
