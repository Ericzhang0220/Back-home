import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReadingComfort {
  small(label: 'Small', textScale: 0.85),
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
  static const String _showHappinessIndexKey = 'show_happiness_index';
  static const String _showLikesStatKey = 'show_likes_stat';
  static const String _showFriendsStatKey = 'show_friends_stat';
  static const String _showActiveStatKey = 'show_active_stat';
  static const String _cameraRotateSensitivityKey = 'camera_rotate_sensitivity';
  static const double _defaultMusicVolume = 0.35;
  static const double _defaultCameraRotateSensitivity = 1.0;

  /// Bounds for the room camera's rotate sensitivity, matching the slider in
  /// the settings screen and the room view's expectations.
  static const double minCameraRotateSensitivity = 0.1;
  static const double maxCameraRotateSensitivity = 2.0;

  SharedPreferences? _preferences;
  ReadingComfort _readingComfort = ReadingComfort.medium;
  double _musicVolume = _defaultMusicVolume;
  bool _showHappinessIndex = true;
  bool _showLikesStat = true;
  bool _showFriendsStat = true;
  bool _showActiveStat = true;
  double _cameraRotateSensitivity = _defaultCameraRotateSensitivity;
  bool _readingComfortDirty = false;
  bool _musicVolumeDirty = false;
  bool _profileVisibilityDirty = false;
  bool _cameraRotateSensitivityDirty = false;

  ReadingComfort get readingComfort => _readingComfort;
  double get musicVolume => _musicVolume;
  double get textScale => _readingComfort.textScale;
  bool get showHappinessIndex => _showHappinessIndex;
  bool get showLikesStat => _showLikesStat;
  bool get showFriendsStat => _showFriendsStat;
  bool get showActiveStat => _showActiveStat;
  double get cameraRotateSensitivity => _cameraRotateSensitivity;

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

      if (!_profileVisibilityDirty) {
        changed =
            _loadVisibilityPreference(
              preferences,
              _showHappinessIndexKey,
              (value) => _showHappinessIndex = value,
              _showHappinessIndex,
            ) ||
            changed;
        changed =
            _loadVisibilityPreference(
              preferences,
              _showLikesStatKey,
              (value) => _showLikesStat = value,
              _showLikesStat,
            ) ||
            changed;
        changed =
            _loadVisibilityPreference(
              preferences,
              _showFriendsStatKey,
              (value) => _showFriendsStat = value,
              _showFriendsStat,
            ) ||
            changed;
        changed =
            _loadVisibilityPreference(
              preferences,
              _showActiveStatKey,
              (value) => _showActiveStat = value,
              _showActiveStat,
            ) ||
            changed;
      }

      if (!_cameraRotateSensitivityDirty) {
        final savedSensitivity = preferences.getDouble(
          _cameraRotateSensitivityKey,
        );
        if (savedSensitivity != null) {
          final normalized = _normalizeCameraRotateSensitivity(
            savedSensitivity,
          );
          if (normalized != _cameraRotateSensitivity) {
            _cameraRotateSensitivity = normalized;
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

  void setPublicProfileVisibility({
    bool? showHappinessIndex,
    bool? showLikesStat,
    bool? showFriendsStat,
    bool? showActiveStat,
  }) {
    var changed = false;

    if (showHappinessIndex != null &&
        _showHappinessIndex != showHappinessIndex) {
      _showHappinessIndex = showHappinessIndex;
      changed = true;
      unawaited(
        _preferences?.setBool(_showHappinessIndexKey, showHappinessIndex),
      );
    }
    if (showLikesStat != null && _showLikesStat != showLikesStat) {
      _showLikesStat = showLikesStat;
      changed = true;
      unawaited(_preferences?.setBool(_showLikesStatKey, showLikesStat));
    }
    if (showFriendsStat != null && _showFriendsStat != showFriendsStat) {
      _showFriendsStat = showFriendsStat;
      changed = true;
      unawaited(_preferences?.setBool(_showFriendsStatKey, showFriendsStat));
    }
    if (showActiveStat != null && _showActiveStat != showActiveStat) {
      _showActiveStat = showActiveStat;
      changed = true;
      unawaited(_preferences?.setBool(_showActiveStatKey, showActiveStat));
    }

    if (!changed) {
      return;
    }

    _profileVisibilityDirty = true;
    notifyListeners();
  }

  Map<String, bool> publicProfileVisibilityMap() {
    return {
      'showHappinessIndex': _showHappinessIndex,
      'showLikesStat': _showLikesStat,
      'showFriendsStat': _showFriendsStat,
      'showActiveStat': _showActiveStat,
    };
  }

  void setCameraRotateSensitivity(double value) {
    final normalized = _normalizeCameraRotateSensitivity(value);
    if (_cameraRotateSensitivity == normalized) {
      return;
    }

    _cameraRotateSensitivity = normalized;
    _cameraRotateSensitivityDirty = true;
    notifyListeners();
    unawaited(_preferences?.setDouble(_cameraRotateSensitivityKey, normalized));
  }

  double _normalizeVolume(double value) {
    return value.clamp(0.0, 1.0).toDouble();
  }

  double _normalizeCameraRotateSensitivity(double value) {
    return value
        .clamp(minCameraRotateSensitivity, maxCameraRotateSensitivity)
        .toDouble();
  }

  bool _loadVisibilityPreference(
    SharedPreferences preferences,
    String key,
    ValueChanged<bool> update,
    bool currentValue,
  ) {
    final savedValue = preferences.getBool(key);
    if (savedValue == null || savedValue == currentValue) {
      return false;
    }

    update(savedValue);
    return true;
  }
}
