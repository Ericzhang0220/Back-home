import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:music_kit/music_kit.dart';

import '../settings/app_settings_controller.dart';

/// Where the room's background music comes from.
enum MusicSource {
  /// The bundled playlist (assets/1.mp3 …) — the default for everyone.
  builtIn,

  /// The player's own Apple Music favorites — opt-in via the room's radio.
  appleMusic,
}

class BackgroundMusicController extends ChangeNotifier {
  BackgroundMusicController({required AppSettingsController settingsController})
    : _settingsController = settingsController {
    _settingsController.addListener(_handleSettingsChanged);
  }

  static const MethodChannel _favoritesChannel = MethodChannel(
    'back_home/apple_music',
  );

  /// Bundled tracks, played in order and looped. Add more filenames here as
  /// they're dropped into assets/ (and listed under `assets:` in pubspec).
  static const List<String> _builtInTracks = ['1.mp3', '2.mp3', '3.mp3'];

  final AppSettingsController _settingsController;
  final MusicKit _musicKit = MusicKit();
  final AudioPlayer _localPlayer = AudioPlayer();

  StreamSubscription<MusicPlayerState>? _playerStateSubscription;
  StreamSubscription<MusicPlayerQueue>? _playerQueueSubscription;
  StreamSubscription<void>? _localCompleteSubscription;

  MusicSource _source = MusicSource.builtIn;
  int _builtInIndex = 0;
  bool _localStarted = false;
  bool _appleInitialized = false;
  bool _isDisposed = false;
  bool _isPreparingQueue = false;
  bool _hasPreparedQueue = false;
  bool _appleUnavailable = false;
  String _statusMessage = 'Playing the Back Home playlist.';
  String? _currentTrackTitle;
  String? _currentTrackSubtitle;

  MusicSource get source => _source;
  bool get isAppleMusicAvailable => _supportsAppleMusic && !_appleUnavailable;
  String get statusMessage => _statusMessage;
  String? get currentTrackTitle => _currentTrackTitle;
  String? get currentTrackSubtitle => _currentTrackSubtitle;

  /// Starts the built-in playlist. Apple Music is *not* touched here — it only
  /// starts once the player opts in through [switchToAppleMusic].
  Future<void> initialize() async {
    if (_isDisposed) {
      return;
    }

    try {
      // We advance the playlist ourselves on completion, so stop (don't loop)
      // at the end of each track.
      await _localPlayer.setReleaseMode(ReleaseMode.stop);
      _localCompleteSubscription = _localPlayer.onPlayerComplete.listen((_) {
        if (_source == MusicSource.builtIn) {
          unawaited(_advanceBuiltIn());
        }
      });
      await _startBuiltIn();
    } catch (_) {
      _setStatus('Background music could not start on this device.');
    }
  }

  Future<void> shutdown() async {
    dispose();
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    _settingsController.removeListener(_handleSettingsChanged);
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_playerQueueSubscription?.cancel());
    unawaited(_localCompleteSubscription?.cancel());
    unawaited(_localPlayer.dispose());

    if (_appleInitialized && isAppleMusicAvailable) {
      unawaited(_pauseAppleDuringShutdown());
    }
    super.dispose();
  }

  // === Source switching (driven by the room's radio) =======================

  /// Opt into Apple Music favorites. Returns false (and stays on the built-in
  /// playlist) when Apple Music isn't available or the player declines access.
  Future<bool> switchToAppleMusic() async {
    if (_isDisposed) {
      return false;
    }
    if (!isAppleMusicAvailable) {
      _setStatus('Apple Music is not available on this device.');
      return false;
    }
    if (_source == MusicSource.appleMusic) {
      return true;
    }

    // Silence the built-in playlist before Apple Music takes over.
    unawaited(_localPlayer.pause());
    _source = MusicSource.appleMusic;
    notifyListeners();

    await _ensureAppleInitialized();
    if (!isAppleMusicAvailable) {
      await switchToBuiltIn();
      return false;
    }

    await _ensureFavoritesPlaying();
    // If Apple Music turned out to be unusable, fall back to the playlist.
    if (!isAppleMusicAvailable || _source != MusicSource.appleMusic) {
      await switchToBuiltIn();
      return false;
    }
    return true;
  }

  /// Return to the bundled playlist (default source).
  Future<void> switchToBuiltIn() async {
    if (_isDisposed) {
      return;
    }
    if (_appleInitialized && _supportsAppleMusic) {
      try {
        await _musicKit.pause();
      } catch (_) {
        // Ignore — we're leaving Apple Music anyway.
      }
    }
    _source = MusicSource.builtIn;
    _currentTrackTitle = null;
    _currentTrackSubtitle = null;
    await _startBuiltIn();
    notifyListeners();
  }

  // === Built-in playlist ===================================================

  Future<void> _startBuiltIn() async {
    if (_isDisposed) {
      return;
    }

    final volume = _settingsController.musicVolume;
    await _localPlayer.setVolume(volume);

    if (volume <= 0) {
      // Muted — keep it paused so we're not decoding audio for nothing.
      await _localPlayer.pause();
      _setStatus('Background music is muted in Back Home.');
      return;
    }

    await _playBuiltInTrack(_builtInIndex);
    _setStatus('Playing the Back Home playlist.');
  }

  Future<void> _playBuiltInTrack(int index) async {
    _builtInIndex = index % _builtInTracks.length;
    _localStarted = true;
    await _localPlayer.play(
      AssetSource(_builtInTracks[_builtInIndex]),
      volume: _settingsController.musicVolume,
    );
    _currentTrackTitle = 'Back Home playlist';
    _currentTrackSubtitle =
        'Track ${_builtInIndex + 1} of ${_builtInTracks.length}';
    notifyListeners();
  }

  Future<void> _advanceBuiltIn() async {
    if (_isDisposed || _source != MusicSource.builtIn) {
      return;
    }
    await _playBuiltInTrack(_builtInIndex + 1);
  }

  // === Settings (volume) ===================================================

  void _handleSettingsChanged() {
    unawaited(_syncPlaybackPreference());
  }

  Future<void> _syncPlaybackPreference() async {
    if (_isDisposed) {
      return;
    }

    if (_source == MusicSource.builtIn) {
      final volume = _settingsController.musicVolume;
      await _localPlayer.setVolume(volume);
      if (volume <= 0) {
        await _localPlayer.pause();
        _setStatus('Background music is muted in Back Home.');
      } else if (_localPlayer.state == PlayerState.playing) {
        // Already playing — the volume change above is all that's needed.
      } else if (_localStarted && _localPlayer.state == PlayerState.paused) {
        await _localPlayer.resume();
        _setStatus('Playing the Back Home playlist.');
      } else {
        await _startBuiltIn();
      }
      return;
    }

    // Apple Music source.
    if (!_appleInitialized || !isAppleMusicAvailable) {
      return;
    }
    try {
      await _applyPlaybackVolume();
      if (_settingsController.musicVolume <= 0) {
        await _musicKit.pause();
        _setStatus('Apple Music is muted in Back Home.');
        return;
      }
      await _ensureFavoritesPlaying();
    } on MissingPluginException {
      _markAppleUnavailable('Apple Music playback is not available here.');
    } catch (_) {
      _markAppleUnavailable('Apple Music could not resume.');
    }
  }

  // === Apple Music =========================================================

  Future<void> _ensureAppleInitialized() async {
    if (_appleInitialized || _isDisposed || !isAppleMusicAvailable) {
      return;
    }

    try {
      _playerStateSubscription = _musicKit.onMusicPlayerStateChanged.listen((
        state,
      ) {
        if (_source != MusicSource.appleMusic) {
          return;
        }
        if (state.playbackStatus == MusicPlayerPlaybackStatus.playing) {
          _setStatus('Playing your Apple Music favorites.');
        } else if (state.playbackStatus == MusicPlayerPlaybackStatus.paused) {
          _setStatus('Apple Music is paused.');
        }
      });

      _playerQueueSubscription = _musicKit.onPlayerQueueChanged.listen((queue) {
        if (_source != MusicSource.appleMusic) {
          return;
        }
        final entry = queue.currentEntry;
        _currentTrackTitle = entry?.title;
        _currentTrackSubtitle = entry?.subtitle;
        notifyListeners();
      });

      _appleInitialized = true;
      await _applyPlaybackVolume();
    } on MissingPluginException {
      _markAppleUnavailable('Apple Music playback is not available here.');
    } catch (_) {
      _markAppleUnavailable('Apple Music could not start on this device.');
    }
  }

  Future<void> _ensureFavoritesPlaying() async {
    if (_isPreparingQueue || _isDisposed || !isAppleMusicAvailable) {
      return;
    }

    _isPreparingQueue = true;
    try {
      final isAuthorized = await _ensureAuthorized();
      if (!isAuthorized || _settingsController.musicVolume <= 0) {
        return;
      }

      if (!_hasPreparedQueue) {
        final queueInfo = await _favoritesChannel
            .invokeMapMethod<String, Object?>(
              'prepareFavoritesQueue',
              <String, Object?>{'limit': 30},
            );

        _hasPreparedQueue = true;
        _currentTrackTitle = queueInfo?['title'] as String?;
        _currentTrackSubtitle = queueInfo?['subtitle'] as String?;
      }

      await _musicKit.setShuffleMode(MusicPlayerShuffleMode.songs);
      await _musicKit.setRepeatMode(MusicPlayerRepeatMode.all);
      await _applyPlaybackVolume();
      await _musicKit.play();
      _setStatus('Playing your Apple Music favorites.');
    } on MissingPluginException {
      _markAppleUnavailable('Apple Music playback is not available here.');
    } on PlatformException catch (error) {
      _markAppleUnavailable(
        error.message ?? 'Apple Music could not prepare songs.',
      );
    } catch (_) {
      _markAppleUnavailable('Apple Music could not prepare songs.');
    } finally {
      _isPreparingQueue = false;
    }
  }

  Future<void> _applyPlaybackVolume() async {
    if (!isAppleMusicAvailable || _isDisposed) {
      return;
    }

    try {
      await _favoritesChannel.invokeMethod<void>(
        'setPlaybackVolume',
        <String, Object?>{'volume': _settingsController.musicVolume},
      );
    } on MissingPluginException {
      rethrow;
    } on PlatformException {
      // Keep playback available if iOS cannot expose the system volume slider.
    }
  }

  Future<bool> _ensureAuthorized() async {
    final currentStatus = await _musicKit.authorizationStatus;
    switch (currentStatus) {
      case MusicAuthorizationStatusAuthorized():
        return true;
      case MusicAuthorizationStatusDenied():
        _setStatus('Apple Music permission is off.');
        return false;
      case MusicAuthorizationStatusRestricted():
        _setStatus('Apple Music is restricted on this device.');
        return false;
      case MusicAuthorizationStatusInitial() ||
          MusicAuthorizationStatusNotDetermined():
        final requestedStatus = await _musicKit.requestAuthorizationStatus(
          startScreenMessage:
              'Back Home can play favorites from your Apple Music library.',
        );
        if (requestedStatus is MusicAuthorizationStatusAuthorized) {
          return true;
        }

        _setStatus('Apple Music permission is needed to play favorites.');
        return false;
    }
  }

  Future<void> _pauseAppleDuringShutdown() async {
    try {
      await _musicKit.pause();
    } catch (_) {
      // Ignore shutdown issues during app teardown.
    }
  }

  void _markAppleUnavailable(String message) {
    _appleUnavailable = true;
    _setStatus(message);
  }

  void _setStatus(String message) {
    if (_statusMessage == message || _isDisposed) {
      return;
    }

    _statusMessage = message;
    notifyListeners();
  }

  bool get _supportsAppleMusic {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS;
  }
}
