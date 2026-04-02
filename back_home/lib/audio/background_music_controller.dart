import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../settings/app_settings_controller.dart';

class BackgroundMusicController {
  BackgroundMusicController({required AppSettingsController settingsController})
    : _settingsController = settingsController {
    _settingsController.addListener(_handleSettingsChanged);
  }

  static const List<String> _playlist = ['1.mp3', '2.mp3', '3.mp3'];

  final AppSettingsController _settingsController;
  AudioPlayer? _player;

  StreamSubscription<void>? _playerCompleteSubscription;
  int _currentTrackIndex = 0;
  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isAudioAvailable = true;
  bool _hasStartedPlayback = false;

  Future<void> initialize() async {
    if (_isInitialized || _isDisposed || !_isAudioAvailable) {
      return;
    }

    try {
      final player = AudioPlayer();
      _player = player;

      await player.setReleaseMode(ReleaseMode.stop);
      _playerCompleteSubscription = player.onPlayerComplete.listen((_) {
        unawaited(_playNextTrack());
      });
      _isInitialized = true;
      await player.setVolume(_settingsController.musicVolume);

      if (_settingsController.musicVolume > 0) {
        await _playCurrentTrack();
      }
    } on MissingPluginException {
      _isAudioAvailable = false;
    } catch (_) {
      _isAudioAvailable = false;
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    _settingsController.removeListener(_handleSettingsChanged);
    await _playerCompleteSubscription?.cancel();

    final player = _player;
    if (_isAudioAvailable && player != null) {
      try {
        await player.dispose();
      } catch (_) {
        // Ignore shutdown issues during app teardown.
      }
    }
  }

  void _handleSettingsChanged() {
    unawaited(_syncVolume());
  }

  Future<void> _syncVolume() async {
    if (!_isInitialized || !_isAudioAvailable || _isDisposed) {
      return;
    }

    final player = _player;
    if (player == null) {
      return;
    }

    try {
      final volume = _settingsController.musicVolume;
      await player.setVolume(volume);

      if (volume <= 0) {
        await player.pause();
        return;
      }

      if (!_hasStartedPlayback) {
        await _playCurrentTrack();
        return;
      }

      if (player.state != PlayerState.playing) {
        await player.resume();
      }
    } on MissingPluginException {
      _isAudioAvailable = false;
    } catch (_) {
      _isAudioAvailable = false;
    }
  }

  Future<void> _playCurrentTrack() async {
    if (!_isInitialized || !_isAudioAvailable || _isDisposed) {
      return;
    }

    final player = _player;
    if (player == null) {
      return;
    }

    try {
      _hasStartedPlayback = true;
      await player.play(
        AssetSource(_playlist[_currentTrackIndex]),
        volume: _settingsController.musicVolume,
      );
    } on MissingPluginException {
      _isAudioAvailable = false;
    } catch (_) {
      _isAudioAvailable = false;
    }
  }

  Future<void> _playNextTrack() async {
    if (_settingsController.musicVolume <= 0) {
      return;
    }

    _currentTrackIndex = (_currentTrackIndex + 1) % _playlist.length;
    await _playCurrentTrack();
  }
}
