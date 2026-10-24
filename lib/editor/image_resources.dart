import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

/// Owns decoded images. Recently painted resources stay resident; cold entries
/// are disposed after the frame has released its references, under byte pressure.
class ImageResources extends MapBase<String, ui.Image> {
  ImageResources(
      {required this.maximumBytes,
      this.evictionDelay = const Duration(seconds: 3),
      this.minimumAge = const Duration(seconds: 2)});
  final Duration evictionDelay, minimumAge;
  final int maximumBytes;
  final _entries = <String, ui.Image>{};
  final _used = <String, DateTime>{};
  int bytes = 0;
  int _leases = 0;
  final _pins = <String, int>{};
  void pin(String key) => _pins.update(key, (n) => n + 1, ifAbsent: () => 1);
  void unpin(String key) {
    final n = (_pins[key] ?? 1) - 1;
    if (n <= 0) {
      _pins.remove(key);
    } else {
      _pins[key] = n;
    }
    _scheduleTrim();
  }

  Timer? _timer;
  @override
  ui.Image? operator [](Object? key) {
    final image = _entries[key];
    if (image != null) _used[key as String] = DateTime.now();
    return image;
  }

  @override
  void operator []=(String key, ui.Image value) {
    final image = value;
    remove(key);
    _entries[key] = image;
    _used[key] = DateTime.now();
    bytes += image.width * image.height * 4;
    _scheduleTrim();
  }

  void _scheduleTrim() {
    if (bytes > maximumBytes &&
        _timer == null &&
        _leases == 0 &&
        _entries.keys.any((key) => !_pins.containsKey(key))) {
      _timer = Timer(evictionDelay, () {
        _timer = null;
        trim();
        _scheduleTrim();
      });
    }
  }

  void trim({Duration? minimumAge, int? targetBytes}) {
    if (_leases != 0) return;
    final cutoff = DateTime.now().subtract(minimumAge ?? this.minimumAge);
    final keys = _entries.keys.toList()
      ..sort((a, b) => _used[a]!.compareTo(_used[b]!));
    for (final key in keys) {
      if (bytes <= (targetBytes ?? maximumBytes)) break;
      if (!_pins.containsKey(key) && !_used[key]!.isAfter(cutoff)) remove(key);
    }
  }

  Future<T> retainDuring<T>(Future<T> Function() work) async {
    _leases++;
    try {
      return await work();
    } finally {
      _leases--;
      _scheduleTrim();
    }
  }

  @override
  Iterable<String> get keys => _entries.keys;
  @override
  ui.Image? remove(Object? key) {
    final image = _entries.remove(key);
    _used.remove(key);
    if (image != null) {
      bytes -= image.width * image.height * 4;
      image.dispose();
    }
    return null;
  }

  @override
  void clear() {
    for (final key in keys.toList()) {
      remove(key);
    }
    _timer?.cancel();
    _timer = null;
  }
}
