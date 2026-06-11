import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:music_kit/music_kit.dart';

import '../settings/app_settings_controller.dart';

class BackgroundMusicController extends ChangeNotifier {
  BackgroundMusicController({required AppSettingsController settingsController})
    : _settingsController = settingsController {
    _settingsController.addListener(_handleSettingsChanged);
  }

  static const MethodChannel _favoritesChannel = MethodChannel(
    'back_home/apple_music',
  );

  final AppSettingsController _settingsController;
  final MusicKit _musicKit = MusicKit();

  StreamSubscription<MusicPlayerState>? _playerStateSubscription;
  StreamSubscription<MusicPlayerQueue>? _playerQueueSubscription;
  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isPreparingQueue = false;
  bool _hasPreparedQueue = false;
  bool _isAppleMusicAvailable = true;
  String _statusMessage = 'Apple Music favorites will play after permission.';
  String? _currentTrackTitle;
  String? _currentTrackSubtitle;

  bool get isAppleMusicAvailable => _isAppleMusicAvailable;
  String get statusMessage => _statusMessage;
  String? get currentTrackTitle => _currentTrackTitle;
  String? get currentTrackSubtitle => _currentTrackSubtitle;

  Future<void> initialize() async {
    if (_isInitialized || _isDisposed || !_isAppleMusicAvailable) {
      return;
    }

    if (!_supportsAppleMusic) {
      _markUnavailable('Apple Music playback is available on iOS devices.');
      return;
    }

    try {
      _playerStateSubscription = _musicKit.onMusicPlayerStateChanged.listen((
        state,
      ) {
        if (state.playbackStatus == MusicPlayerPlaybackStatus.playing) {
          _setStatus('Playing your Apple Music favorites.');
        } else if (state.playbackStatus == MusicPlayerPlaybackStatus.paused) {
          _setStatus('Apple Music is paused.');
        }
      });

      _playerQueueSubscription = _musicKit.onPlayerQueueChanged.listen((queue) {
        final entry = queue.currentEntry;
        _currentTrackTitle = entry?.title;
        _currentTrackSubtitle = entry?.subtitle;
        notifyListeners();
      });

      _isInitialized = true;
      await _applyPlaybackVolume();
      if (_settingsController.musicVolume > 0) {
        await _ensureFavoritesPlaying();
      }
    } on MissingPluginException {
      _markUnavailable('Apple Music playback is not available here.');
    } catch (_) {
      _markUnavailable('Apple Music could not start on this device.');
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

    if (_isAppleMusicAvailable) {
      unawaited(_pauseDuringShutdown());
    }
    super.dispose();
  }

  Future<void> _pauseDuringShutdown() async {
    try {
      await _musicKit.pause();
    } catch (_) {
      // Ignore shutdown issues during app teardown.
    }
  }

  void _handleSettingsChanged() {
    unawaited(_syncPlaybackPreference());
  }

  Future<void> _syncPlaybackPreference() async {
    if (!_isInitialized || !_isAppleMusicAvailable || _isDisposed) {
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
      _markUnavailable('Apple Music playback is not available here.');
    } catch (_) {
      _markUnavailable('Apple Music could not resume.');
    }
  }

  Future<void> _ensureFavoritesPlaying() async {
    if (_isPreparingQueue || _isDisposed) {
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
      _markUnavailable('Apple Music playback is not available here.');
    } on PlatformException catch (error) {
      _markUnavailable(error.message ?? 'Apple Music could not prepare songs.');
    } catch (_) {
      _markUnavailable('Apple Music could not prepare songs.');
    } finally {
      _isPreparingQueue = false;
    }
  }

  Future<void> _applyPlaybackVolume() async {
    if (!_isAppleMusicAvailable || _isDisposed || !_supportsAppleMusic) {
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

  void _markUnavailable(String message) {
    _isAppleMusicAvailable = false;
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
