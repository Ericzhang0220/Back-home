import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../rooms/moon_state.dart';
import 'weather_service.dart';

/// USNO supplies local-noon illumination. Advance it to the current instant,
/// then apply the observer's hemisphere and locally visible eclipse events.
class MoonService {
  MoonService({http.Client? client, Future<Position?> Function()? location})
    : _client = client ?? http.Client(),
      _location = location ?? WeatherService.instance.moonPosition;
  static final instance = MoonService();
  final http.Client _client;
  final Future<Position?> Function() _location;
  String? _cacheKey;
  double? _noonProgress;
  DateTime? _retryAfter;
  Future<MoonState>? _pending;

  Future<MoonState> current({DateTime? time}) {
    if (_pending != null) return _pending!;
    final task = _load(time ?? DateTime.now());
    _pending = task;
    return task.whenComplete(() => _pending = null);
  }

  Future<MoonState> _load(DateTime now) async {
    Position? position;
    try {
      position = await _location();
    } catch (_) {
      /* Offline cycle below. */
    }
    if (position == null) return MoonState.estimate(now);
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final key =
        '$date/${position.latitude.toStringAsFixed(1)}/${position.longitude.toStringAsFixed(1)}/${now.timeZoneOffset.inMinutes}';
    if (_cacheKey != key &&
        (_retryAfter == null || !now.isBefore(_retryAfter!))) {
      try {
        final uri = Uri.https('aa.usno.navy.mil', '/api/rstt/oneday', {
          'date': date,
          'coords':
              '${position.latitude.toStringAsFixed(2)},${position.longitude.toStringAsFixed(2)}',
          'tz': '${now.timeZoneOffset.inMinutes / 60}',
        });
        final response = await _client
            .get(uri)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) {
          throw const FormatException('Moon data unavailable');
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['error'] != null) {
          throw const FormatException('Moon data unavailable');
        }
        final data = (body['properties'] as Map)['data'] as Map;
        if (data['year'] != now.year ||
            data['month'] != now.month ||
            data['day'] != now.day) {
          throw const FormatException('Stale moon data');
        }
        _noonProgress = progressFromUsno(data);
        _cacheKey = key;
        _retryAfter = null;
      } catch (_) {
        _retryAfter = now.add(const Duration(minutes: 20));
      }
    }
    double? progress;
    if (_cacheKey == key && _noonProgress != null) {
      final noon = now.isUtc
          ? DateTime.utc(now.year, now.month, now.day, 12)
          : DateTime(now.year, now.month, now.day, 12);
      progress =
          (_noonProgress! +
              now.difference(noon).inMilliseconds /
                  Duration.millisecondsPerDay /
                  29.530588853 +
              1) %
          1;
    }
    return MoonState.estimate(
      now,
      latitude: position.latitude,
      longitude: position.longitude,
      progress: progress,
    );
  }

  static double progressFromUsno(Map data) {
    final raw = data['fracillum'];
    final fraction = raw is String
        ? double.tryParse(raw.replaceAll('%', ''))
        : null;
    final phase = data['curphase'];
    const phases = {
      'New Moon',
      'Waxing Crescent',
      'First Quarter',
      'Waxing Gibbous',
      'Full Moon',
      'Waning Gibbous',
      'Last Quarter',
      'Waning Crescent',
    };
    if (fraction == null ||
        !fraction.isFinite ||
        fraction < 0 ||
        fraction > 100 ||
        !phases.contains(phase)) {
      throw const FormatException('Invalid moon phase');
    }
    final waxing = math.acos(1 - 2 * fraction / 100) / (2 * math.pi);
    return phase == 'Last Quarter' || (phase as String).startsWith('Waning')
        ? 1 - waxing
        : waxing;
  }
}
