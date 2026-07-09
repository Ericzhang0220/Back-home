import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../rooms/room_state.dart';

/// Fetches the current real-world weather from Open-Meteo and maps it onto the
/// room's [SkyWeather] enum so the sky beyond the window mirrors the outside.
///
/// A single request pulls the whole local day's hourly weather codes
/// (`hourly=weather_code`, `forecast_days=1`, `timezone=auto`), which returns 24
/// entries indexed 0=00:00 … 23=23:00 in the location's own timezone. The room's
/// sky reads the device clock for time-of-day, so we simply index that array by
/// the current hour — advancing through the day costs **no** extra network
/// calls. The forecast itself is only re-fetched once the cache passes [_ttl].
class WeatherService {
  WeatherService._();

  /// Shared instance — weather is a whole-app, whole-day concern, so a single
  /// cache serves every screen.
  static final WeatherService instance = WeatherService._();

  /// How long a fetched forecast is trusted before we pull a fresh one. Three
  /// hours keeps conditions current without hammering the free tier (Open-Meteo
  /// rate-limits per IP, and this is called directly from the device).
  static const Duration _ttl = Duration(hours: 3);

  /// Hourly WMO weather codes for the current local day, index = hour 0–23.
  List<int?>? _hourlyCodes;
  DateTime? _fetchedAt;

  bool _inFlight = false;

  /// Returns the weather to show for the current hour, fetching a fresh forecast
  /// only when the cache is empty or stale. Returns `null` if location or the
  /// network is unavailable so callers can fall back to a default sky.
  Future<SkyWeather?> currentSkyWeather({bool forceRefresh = false}) async {
    final now = DateTime.now();

    final cacheValid =
        _hourlyCodes != null &&
        _fetchedAt != null &&
        now.difference(_fetchedAt!) < _ttl;
    if (!forceRefresh && cacheValid) {
      return _skyForHour(now.hour);
    }

    // Avoid firing overlapping requests (e.g. rapid rebuilds). If a fetch is
    // already running, hand back whatever we last cached.
    if (_inFlight) {
      return _hourlyCodes == null ? null : _skyForHour(now.hour);
    }

    _inFlight = true;
    try {
      final position = await _resolvePosition();
      if (position == null) {
        return _hourlyCodes == null ? null : _skyForHour(now.hour);
      }

      final codes = await _fetchHourlyCodes(
        position.latitude,
        position.longitude,
      );
      if (codes == null) {
        return _hourlyCodes == null ? null : _skyForHour(now.hour);
      }

      _hourlyCodes = codes;
      _fetchedAt = DateTime.now();
      return _skyForHour(DateTime.now().hour);
    } finally {
      _inFlight = false;
    }
  }

  /// The cached weather for a given local hour without touching the network.
  /// Lets the sky re-derive as the clock advances between fetches.
  SkyWeather? weatherForHour(int hour) {
    final codes = _hourlyCodes;
    if (codes == null) {
      return null;
    }
    return _skyForHour(hour);
  }

  SkyWeather? _skyForHour(int hour) {
    final codes = _hourlyCodes;
    if (codes == null || codes.isEmpty) {
      return null;
    }
    final code = codes[hour.clamp(0, codes.length - 1)];
    return code == null ? null : _skyForCode(code);
  }

  /// Resolves the device location, requesting permission if needed. Returns
  /// `null` when services are off or permission is denied.
  Future<Position?> _resolvePosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      // Current weather only needs a rough location; low accuracy is faster and
      // lighter on battery, and a cached fix is fine if one is recent.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return last;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Requests the day's hourly weather codes from Open-Meteo. `timezone=auto`
  /// aligns the array to the location's local midnight so index == hour.
  Future<List<int?>?> _fetchHourlyCodes(double lat, double lon) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'hourly': 'weather_code',
      'forecast_days': '1',
      'timezone': 'auto',
    });

    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final hourly = body['hourly'] as Map<String, dynamic>?;
      final raw = hourly?['weather_code'] as List<dynamic>?;
      if (raw == null || raw.isEmpty) {
        return null;
      }

      return [
        for (final value in raw) value is num ? value.toInt() : null,
      ];
    } catch (_) {
      return null;
    }
  }

  /// Maps a WMO weather interpretation code to the four-way room sky.
  /// See https://open-meteo.com/en/docs — codes 0–3 are the cloud-cover ramp;
  /// anything drizzle/rain/snow/shower/thunderstorm reads as rain.
  static SkyWeather _skyForCode(int code) {
    return switch (code) {
      0 || 1 => SkyWeather.clear,
      2 => SkyWeather.cloudy,
      3 || 45 || 48 => SkyWeather.overcast,
      _ => SkyWeather.rain,
    };
  }
}
