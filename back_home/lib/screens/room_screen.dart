import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../audio/background_music_controller.dart';
import '../rooms/isometric_room_view.dart';
import '../rooms/room_gl_gate.dart';
import '../rooms/room_state.dart';
import '../services/weather_service.dart';
import '../settings/app_settings_controller.dart';
import '../widgets/app_ui.dart';
import '../widgets/weather_settings_controls.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.controller,
    required this.settingsController,
    required this.musicController,
    required this.onOpenShop,
    required this.isActive,
    required this.isChromeVisible,
    required this.isChromeInteractive,
    required this.onRevealChrome,
    required this.onSubviewChanged,
  });

  final RoomEditorController controller;
  final AppSettingsController settingsController;
  final BackgroundMusicController musicController;
  final VoidCallback onOpenShop;
  final bool isActive;
  final bool isChromeVisible;
  final bool isChromeInteractive;
  final VoidCallback onRevealChrome;

  /// Reports whether the room is in a focused subview (desk or night mode) so
  /// the app can hide the nav bar outside the main view.
  final ValueChanged<bool> onSubviewChanged;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  static const Duration _nightHintFadeDelay = Duration(seconds: 4);
  static const Duration _nightGlowDimDelay = Duration(seconds: 6);
  static const Duration _nightExitBrightenDelay = Duration(milliseconds: 100);
  static const Duration _nightOverlayFadeIn = Duration(milliseconds: 1600);
  static const Duration _nightOverlayFadeOut = Duration(milliseconds: 400);
  // Chrome fade timing — kept in sync with app.dart's room-chrome durations.
  static const Duration _chromeFadeIn = Duration(milliseconds: 320);
  static const Duration _chromeFadeOut = Duration(seconds: 2);

  // How often the live sky re-derives weather from the cached forecast. This
  // only hits the network when the cache passes its TTL; otherwise it just
  // re-indexes the day's hourly codes so the sky follows the clock.
  static const Duration _weatherRefreshInterval = Duration(minutes: 20);

  Timer? _nightHintFadeTimer;
  Timer? _nightGlowDimTimer;
  Timer? _nightExitTimer;
  Timer? _weatherTimer;
  bool _panelOpen = false;
  bool _deskFocused = false;
  bool _nightMode = false;
  bool _outsideView = false;
  bool _nightHintVisible = false;
  bool _nightGlowDimmed = false;
  SkyWeather? _autoWeather; // latest reading from WeatherService
  double _cameraZoom = 1.0;
  bool _showFurnitureColliders = false;

  bool get _inSubview => _deskFocused || _nightMode || _outsideView;

  /// Weather actually shown through the window: the live reading when Auto is
  /// on (falling back to the manual value until the first fetch lands),
  /// otherwise the manually chosen weather.
  SkyWeather get _effectiveWeather => widget.settingsController.weatherAuto
      ? (_autoWeather ?? widget.settingsController.skyWeather)
      : widget.settingsController.skyWeather;

  @override
  void initState() {
    super.initState();
    _refreshWeather();
    _weatherTimer = Timer.periodic(
      _weatherRefreshInterval,
      (_) => _refreshWeather(),
    );
  }

  Future<void> _refreshWeather() async {
    final weather = await WeatherService.instance.currentSkyWeather();
    if (!mounted || weather == null) {
      return;
    }
    setState(() => _autoWeather = weather);
  }

  @override
  void dispose() {
    _nightHintFadeTimer?.cancel();
    _nightGlowDimTimer?.cancel();
    _nightExitTimer?.cancel();
    _weatherTimer?.cancel();
    super.dispose();
  }

  void _togglePanel() {
    setState(() {
      _panelOpen = !_panelOpen;
    });
  }

  void _closePanel() {
    if (!_panelOpen) {
      return;
    }
    setState(() {
      _panelOpen = false;
    });
  }

  void _focusDesk() {
    _nightHintFadeTimer?.cancel();
    _nightGlowDimTimer?.cancel();
    _nightExitTimer?.cancel();
    setState(() {
      _deskFocused = true;
      _nightMode = false;
      _outsideView = false;
      _nightHintVisible = false;
      _nightGlowDimmed = false;
      _panelOpen = false;
    });
    widget.onSubviewChanged(_inSubview);
  }

  void _openNightMode() {
    setState(() {
      _deskFocused = false;
      _nightMode = true;
      _outsideView = false;
      _nightHintVisible = true;
      _nightGlowDimmed = false;
      _panelOpen = false;
    });
    widget.onSubviewChanged(_inSubview);
    _scheduleNightHintFade();
    _scheduleNightGlowDim();
  }

  void _restoreRoomLight() {
    _nightHintFadeTimer?.cancel();
    _nightGlowDimTimer?.cancel();
    _nightExitTimer?.cancel();
    setState(() {
      _nightMode = false;
      _deskFocused = false;
      _nightHintVisible = false;
      _nightGlowDimmed = false;
    });
    // Back in the main view, but leave the nav hidden until a double-tap.
    widget.onSubviewChanged(_inSubview);
  }

  void _openOutsideView() {
    _nightHintFadeTimer?.cancel();
    _nightGlowDimTimer?.cancel();
    _nightExitTimer?.cancel();
    setState(() {
      _deskFocused = false;
      _nightMode = false;
      _outsideView = true;
      _nightHintVisible = false;
      _nightGlowDimmed = false;
      _panelOpen = false;
    });
    widget.onSubviewChanged(_inSubview);
  }

  void _handleDoubleTap() {
    if (_outsideView) {
      setState(() {
        _outsideView = false;
      });
      widget.onSubviewChanged(_inSubview);
      return;
    }
    if (_nightMode) {
      _brightenNightOverlayBeforeExit();
      return;
    }
    if (_deskFocused) {
      // Leave the desk subview for the main room view, keeping the nav hidden —
      // a second double-tap (handled below) is what brings it up.
      setState(() {
        _deskFocused = false;
      });
      widget.onSubviewChanged(_inSubview);
      return;
    }
    // Already in the main room view: this double-tap reveals the nav bar.
    widget.onRevealChrome();
  }

  void _scheduleNightHintFade() {
    _nightHintFadeTimer?.cancel();
    _nightHintFadeTimer = Timer(_nightHintFadeDelay, () {
      if (!mounted || !_nightMode) {
        return;
      }
      setState(() {
        _nightHintVisible = false;
      });
    });
  }

  void _scheduleNightGlowDim() {
    _nightGlowDimTimer?.cancel();
    _nightGlowDimTimer = Timer(_nightGlowDimDelay, () {
      if (!mounted || !_nightMode) {
        return;
      }
      setState(() {
        _nightGlowDimmed = true;
      });
    });
  }

  void _brightenNightOverlayBeforeExit() {
    _nightGlowDimTimer?.cancel();
    _nightExitTimer?.cancel();
    setState(() {
      _nightGlowDimmed = false;
    });
    _nightExitTimer = Timer(_nightExitBrightenDelay, () {
      if (!mounted || !_nightMode) {
        return;
      }
      _restoreRoomLight();
    });
  }

  void _openRadioSheet() {
    final music = widget.musicController;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: music,
          builder: (context, _) {
            return _RadioSheet(
              source: music.source,
              statusMessage: music.statusMessage,
              appleMusicAvailable: music.isAppleMusicAvailable,
              trackTitle: music.currentTrackTitle,
              trackSubtitle: music.currentTrackSubtitle,
              onSelectBuiltIn: () => music.switchToBuiltIn(),
              onSelectAppleMusic: () => music.switchToAppleMusic(),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final panelHeight = isLandscape
        ? math.min(media.size.height - media.padding.vertical - 24, 420.0)
        : math.min(media.size.height * 0.62, 520.0);
    final panelWidth = isLandscape
        ? math.min(media.size.width - media.padding.horizontal - 24, 560.0)
        : double.infinity;

    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.settingsController,
      ]),
      builder: (context, _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _handleDoubleTap,
          onLongPress: _togglePanel,
          child: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<Object?>(
                  valueListenable: RoomGlGate.activeOwner,
                  builder: (context, glOwner, _) {
                    // The furniture editor and the shop's 3D previews run their
                    // own renderers, and mobile GL can't keep two live at once.
                    // While either holds the claim we drop this view entirely so
                    // its context is released; on return it rebuilds fresh (new
                    // State -> new renderer), which is what un-freezes the
                    // camera after an edit.
                    if (glOwner != null) {
                      return const ColoredBox(color: Color(0xFF191513));
                    }
                    return IsometricRoomView(
                      controller: widget.controller,
                      isActive: widget.isActive,
                      canMoveFurniture: false,
                      deskFocused: _deskFocused,
                      nightMode: _nightMode,
                      outsideView: _outsideView,
                      onTapDesk: _focusDesk,
                      onTapBed: _openNightMode,
                      onTapRadio: _openRadioSheet,
                      onTapWindow: _openOutsideView,
                      onDoubleTapRoom: _handleDoubleTap,
                      skyWeather: _effectiveWeather,
                      skyTimeOfDay: widget.settingsController.skyTimeOfDay,
                      cameraZoom: _cameraZoom,
                      cameraRotateSensitivity:
                          widget.settingsController.cameraRotateSensitivity,
                      showFurnitureColliders: _showFurnitureColliders,
                    );
                  },
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(
                            alpha: _outsideView ? 0.12 : 0.48,
                          ),
                          Colors.transparent,
                          Colors.black.withValues(
                            alpha: _outsideView ? 0.04 : 0.18,
                          ),
                        ],
                        stops: const [0, 0.36, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: media.padding.top + 16,
                left: media.padding.left + 20,
                right: media.padding.right + 20,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (kDebugMode)
                      Tooltip(
                        message: _showFurnitureColliders
                            ? 'Hide furniture colliders'
                            : 'Show furniture colliders',
                        child: _SceneButton(
                          icon: _showFurnitureColliders
                              ? Icons.view_in_ar_rounded
                              : Icons.view_in_ar_outlined,
                          onTap: () {
                            setState(() {
                              _showFurnitureColliders =
                                  !_showFurnitureColliders;
                            });
                          },
                        ),
                      ),
                    Expanded(
                      child: Container(),
                      // child: _FloatingTitle(
                      //   title: 'Bedroom editor',
                      //   subtitle: selectedDefinition?.title ?? 'Direct room view',
                      // ),
                    ),
                    IgnorePointer(
                      ignoring: !widget.isChromeInteractive,
                      child: AnimatedOpacity(
                        // Fade in fast on reveal, fade out slowly — matches the
                        // floating nav card timing in app.dart.
                        duration: widget.isChromeVisible
                            ? _chromeFadeIn
                            : _chromeFadeOut,
                        curve: Curves.easeInOutCubic,
                        opacity: widget.isChromeVisible ? 1 : 0,
                        child: _SceneButton(
                          icon: Icons.shopping_bag_rounded,
                          onTap: widget.onOpenShop,
                        ),
                      ),
                    ),
                    // const SizedBox(width: 12),
                    // _SceneButton(
                    //   icon: _panelOpen ? Icons.close_rounded : Icons.tune_rounded,
                    //   onTap: _togglePanel,
                    //   highlighted: true,
                    // ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_nightMode,
                  child: AnimatedOpacity(
                    duration: _nightMode
                        ? _nightOverlayFadeIn
                        : _nightOverlayFadeOut,
                    curve: Curves.easeInOutCubic,
                    opacity: _nightMode ? 1 : 0,
                    child: _GoodNightOverlay(
                      showHint: _nightHintVisible,
                      dimBrightElements: _nightGlowDimmed,
                    ),
                  ),
                ),
              ),
              if (_panelOpen)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _closePanel,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.18),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: IgnorePointer(
                    ignoring: !_panelOpen,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      offset: _panelOpen ? Offset.zero : const Offset(0, 1.08),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: panelWidth),
                          child: _SettingsPanel(
                            height: panelHeight,
                            skyWeather: widget.settingsController.skyWeather,
                            weatherAuto: widget.settingsController.weatherAuto,
                            skyTimeOfDay:
                                widget.settingsController.skyTimeOfDay,
                            cameraZoom: _cameraZoom,
                            cameraRotateSensitivity: widget
                                .settingsController
                                .cameraRotateSensitivity,
                            onSkyWeather:
                                widget.settingsController.setSkyWeather,
                            onWeatherAuto: () {
                              widget.settingsController.setWeatherAuto();
                              _refreshWeather();
                            },
                            onSkyTimeOfDay:
                                widget.settingsController.setSkyTimeOfDay,
                            onCameraZoom: (value) =>
                                setState(() => _cameraZoom = value),
                            onCameraRotateSensitivity: widget
                                .settingsController
                                .setCameraRotateSensitivity,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GoodNightOverlay extends StatelessWidget {
  const _GoodNightOverlay({
    required this.showHint,
    required this.dimBrightElements,
  });

  final bool showHint;
  final bool dimBrightElements;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final brightElementsOpacity = dimBrightElements ? 0.34 : 1.0;

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xE9000000)),
      child: Stack(
        children: [
          Positioned(
            top: topPadding + 82,
            right: 52,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOutCubic,
              opacity: brightElementsOpacity,
              child: Container(
                width: 92,
                height: 92,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFE2E0D2),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x77E7E1C9),
                      blurRadius: 34,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: Align(
                  alignment: const Alignment(0.28, -0.12),
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xE9000000),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeInOutCubic,
                    opacity: brightElementsOpacity,
                    child: const Text(
                      'Have a good night! See you tomorrow.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFF5F0E8),
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    duration: showHint
                        ? const Duration(milliseconds: 350)
                        : const Duration(milliseconds: 900),
                    curve: Curves.easeInOutCubic,
                    opacity: showHint ? 1 : 0,
                    child: const Text(
                      '(Your room is now in night mode. If you want to go back, just double click the scene.)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFF5F0E8),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.height,
    required this.skyWeather,
    required this.weatherAuto,
    required this.skyTimeOfDay,
    required this.cameraZoom,
    required this.cameraRotateSensitivity,
    required this.onSkyWeather,
    required this.onWeatherAuto,
    required this.onSkyTimeOfDay,
    required this.onCameraZoom,
    required this.onCameraRotateSensitivity,
  });

  final double height;
  final SkyWeather skyWeather;
  final bool weatherAuto;
  final double? skyTimeOfDay;
  final double cameraZoom;
  final double cameraRotateSensitivity;
  final ValueChanged<SkyWeather> onSkyWeather;
  final VoidCallback onWeatherAuto;
  final ValueChanged<double> onSkyTimeOfDay;
  final ValueChanged<double> onCameraZoom;
  final ValueChanged<double> onCameraRotateSensitivity;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          constraints: BoxConstraints(maxHeight: height),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          decoration: BoxDecoration(
            color: const Color(0xFFF8EFE4).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2A000000),
                blurRadius: 32,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD3BAA9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Weather',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Weather and time of day shown through the window.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                const SizedBox(height: 10),
                WeatherSettingsControls(
                  skyWeather: skyWeather,
                  weatherAuto: weatherAuto,
                  skyTimeOfDay: skyTimeOfDay,
                  onSkyWeather: onSkyWeather,
                  onWeatherAuto: onWeatherAuto,
                  onSkyTimeOfDay: onSkyTimeOfDay,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Camera',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                _CameraSlider(
                  label: 'Zoom',
                  valueLabel: '${(cameraZoom * 100).round()}%',
                  value: cameraZoom,
                  min: 0.75,
                  max: 1.4,
                  divisions: 13,
                  onChanged: onCameraZoom,
                ),
                _CameraSlider(
                  label: 'Rotate',
                  valueLabel: '${cameraRotateSensitivity.toStringAsFixed(1)}x',
                  value: cameraRotateSensitivity,
                  min: 0.1,
                  max: 2.0,
                  divisions: 14,
                  onChanged: onCameraRotateSensitivity,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SceneButton extends StatelessWidget {
  const _SceneButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.black.withValues(alpha: 0.28),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 54,
              height: 54,
              child: Icon(icon, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraSlider extends StatelessWidget {
  const _CameraSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
        ),
      ],
    );
  }
}

/// The radio's music picker: choose the built-in playlist or Apple Music.
class _RadioSheet extends StatelessWidget {
  const _RadioSheet({
    required this.source,
    required this.statusMessage,
    required this.appleMusicAvailable,
    required this.trackTitle,
    required this.trackSubtitle,
    required this.onSelectBuiltIn,
    required this.onSelectAppleMusic,
  });

  final MusicSource source;
  final String statusMessage;
  final bool appleMusicAvailable;
  final String? trackTitle;
  final String? trackSubtitle;
  final VoidCallback onSelectBuiltIn;
  final VoidCallback onSelectAppleMusic;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD3BAA9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.radio_rounded, color: AppColors.clay),
                  const SizedBox(width: 10),
                  const Text(
                    'Radio',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                statusMessage,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              if (trackTitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  trackSubtitle == null
                      ? trackTitle!
                      : '$trackTitle • $trackSubtitle',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _RadioOption(
                icon: Icons.library_music_rounded,
                title: 'Back Home playlist',
                detail: 'The built-in tracks that ship with the app.',
                selected: source == MusicSource.builtIn,
                onTap: () {
                  onSelectBuiltIn();
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 10),
              _RadioOption(
                icon: Icons.apple_rounded,
                title: 'Apple Music favorites',
                detail: appleMusicAvailable
                    ? 'Shuffle songs from your Apple Music library.'
                    : 'Not available on this device.',
                selected: source == MusicSource.appleMusic,
                enabled: appleMusicAvailable,
                onTap: () {
                  onSelectAppleMusic();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioOption extends StatelessWidget {
  const _RadioOption({
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: selected ? AppColors.blush.withValues(alpha: 0.5) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: AppColors.clay),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle_rounded, color: AppColors.sage),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
