import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReadingComfort {
  small(label: 'Small', textScale: 0.9),
  medium(label: 'Medium', textScale: 1.0),
  large(label: 'Large', textScale: 1.15);

  const ReadingComfort({required this.label, required this.textScale});

  final String label;
  final double textScale;

  static ReadingComfort fromLabel(String? label) {
    return ReadingComfort.values.firstWhere(
      (option) => option.label == label,
      orElse: () => ReadingComfort.medium,
    );
  }
}

class AppSettingsController extends ChangeNotifier {
  AppSettingsController();

  static const String _readingComfortKey = 'reading_comfort';
  static const String _musicVolumeKey = 'music_volume';
  static const double _defaultMusicVolume = 0.35;

  SharedPreferences? _preferences;
  ReadingComfort _readingComfort = ReadingComfort.medium;
  double _musicVolume = _defaultMusicVolume;
  bool _readingComfortDirty = false;
  bool _musicVolumeDirty = false;

  ReadingComfort get readingComfort => _readingComfort;
  double get musicVolume => _musicVolume;
  double get textScale => _readingComfort.textScale;

  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _preferences = preferences;

      var changed = false;

      if (!_readingComfortDirty) {
        final savedReadingComfort = ReadingComfort.fromLabel(
          preferences.getString(_readingComfortKey),
        );
        if (savedReadingComfort != _readingComfort) {
          _readingComfort = savedReadingComfort;
          changed = true;
        }
      }

      if (!_musicVolumeDirty) {
        final savedMusicVolume = preferences.getDouble(_musicVolumeKey);
        if (savedMusicVolume != null) {
          final normalizedVolume = _normalizeVolume(savedMusicVolume);
          if (normalizedVolume != _musicVolume) {
            _musicVolume = normalizedVolume;
            changed = true;
          }
        }
      }

      if (changed) {
        notifyListeners();
      }
    } catch (_) {
      // Keep defaults if preferences are unavailable in tests or on startup.
    }
  }

  void setReadingComfort(ReadingComfort value) {
    if (_readingComfort == value) {
      return;
    }

    _readingComfort = value;
    _readingComfortDirty = true;
    notifyListeners();
    unawaited(_preferences?.setString(_readingComfortKey, value.label));
  }

  void setMusicVolume(double value) {
    final normalizedVolume = _normalizeVolume(value);
    if (_musicVolume == normalizedVolume) {
      return;
    }

    _musicVolume = normalizedVolume;
    _musicVolumeDirty = true;
    notifyListeners();
    unawaited(_preferences?.setDouble(_musicVolumeKey, normalizedVolume));
  }

  double _normalizeVolume(double value) {
    return value.clamp(0.0, 1.0).toDouble();
  }
}
