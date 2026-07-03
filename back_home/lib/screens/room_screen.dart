import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../rooms/isometric_room_view.dart';
import '../rooms/room_state.dart';
import '../rooms/room_visuals.dart';
import '../widgets/app_ui.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.controller,
    required this.onOpenShop,
    required this.isActive,
    required this.isChromeVisible,
    required this.isChromeInteractive,
    required this.onRevealChrome,
    required this.onSubviewChanged,
  });

  final RoomEditorController controller;
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
  static const Duration _nightHintFadeDelay = Duration(seconds: 5);
  static const Duration _nightGlowDimDelay = Duration(seconds: 3);
  static const Duration _nightExitBrightenDelay = Duration(milliseconds: 650);
  // Chrome fade timing — kept in sync with app.dart's room-chrome durations.
  static const Duration _chromeFadeIn = Duration(milliseconds: 320);
  static const Duration _chromeFadeOut = Duration(seconds: 2);

  Timer? _nightHintFadeTimer;
  Timer? _nightGlowDimTimer;
  Timer? _nightExitTimer;
  bool _panelOpen = false;
  bool _deskFocused = false;
  bool _nightMode = false;
  bool _nightHintVisible = false;
  bool _nightGlowDimmed = false;
  SkyWeather _skyWeather = SkyWeather.clear;
  double? _skyTimeOfDay; // null = live (real clock)
  double _cameraZoom = 1.0;
  double _cameraRotateSensitivity = 1.0;

  bool get _inSubview => _deskFocused || _nightMode;

  @override
  void dispose() {
    _nightHintFadeTimer?.cancel();
    _nightGlowDimTimer?.cancel();
    _nightExitTimer?.cancel();
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

  void _handleDoubleTap() {
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

  void _showResult(RoomActionResult result) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final panelHeight = math.min(media.size.height * 0.62, 520.0);

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final selectedItem = widget.controller.selectedItemId == null
            ? null
            : widget.controller.placedItemById(
                widget.controller.selectedItemId!,
              );
        final selectedDefinition = selectedItem == null
            ? null
            : widget.controller.definitionFor(selectedItem.definitionId);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _handleDoubleTap,
          onLongPress: _togglePanel,
          child: Stack(
            children: [
              Positioned.fill(
                child: IsometricRoomView(
                  controller: widget.controller,
                  isActive: widget.isActive,
                  canMoveFurniture: false,
                  deskFocused: _deskFocused,
                  nightMode: _nightMode,
                  onTapDesk: _focusDesk,
                  onTapBed: _openNightMode,
                  onDoubleTapRoom: _handleDoubleTap,
                  skyWeather: _skyWeather,
                  skyTimeOfDay: _skyTimeOfDay,
                  cameraZoom: _cameraZoom,
                  cameraRotateSensitivity: _cameraRotateSensitivity,
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
                          Colors.black.withValues(alpha: 0.48),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.18),
                        ],
                        stops: const [0, 0.36, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: media.padding.top + 16,
                left: 20,
                right: 20,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
              if (_deskFocused && !_nightMode)
                Positioned(
                  top: media.padding.top + 84,
                  left: 18,
                  child: _SceneButton(
                    icon: Icons.keyboard_arrow_left_rounded,
                    onTap: () {
                      setState(() {
                        _deskFocused = false;
                      });
                      // Return to the main view with the nav still hidden.
                      widget.onSubviewChanged(_inSubview);
                    },
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_nightMode,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 1600),
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
                        child: _SettingsPanel(
                          height: panelHeight,
                          controller: widget.controller,
                          selectedItem: selectedItem,
                          selectedDefinition: selectedDefinition,
                          onClose: _closePanel,
                          onOpenShop: widget.onOpenShop,
                          onAddOwnedItem: (definitionId) => _showResult(
                            widget.controller.addOwnedItem(definitionId),
                          ),
                          onRotateSelected: selectedItem == null
                              ? null
                              : () => _showResult(
                                  widget.controller.rotatePlacedItem(
                                    selectedItem.instanceId,
                                  ),
                                ),
                          onStoreSelected: selectedItem == null
                              ? null
                              : () => _showResult(
                                  widget.controller.storePlacedItem(
                                    selectedItem.instanceId,
                                  ),
                                ),
                          skyWeather: _skyWeather,
                          skyTimeOfDay: _skyTimeOfDay,
                          cameraZoom: _cameraZoom,
                          cameraRotateSensitivity: _cameraRotateSensitivity,
                          onSkyWeather: (w) => setState(() => _skyWeather = w),
                          onSkyTimeOfDay: (t) =>
                              setState(() => _skyTimeOfDay = t),
                          onCameraZoom: (value) =>
                              setState(() => _cameraZoom = value),
                          onCameraRotateSensitivity: (value) =>
                              setState(() => _cameraRotateSensitivity = value),
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
    required this.controller,
    required this.selectedItem,
    required this.selectedDefinition,
    required this.onClose,
    required this.onOpenShop,
    required this.onAddOwnedItem,
    required this.onRotateSelected,
    required this.onStoreSelected,
    required this.skyWeather,
    required this.skyTimeOfDay,
    required this.cameraZoom,
    required this.cameraRotateSensitivity,
    required this.onSkyWeather,
    required this.onSkyTimeOfDay,
    required this.onCameraZoom,
    required this.onCameraRotateSensitivity,
  });

  final double height;
  final RoomEditorController controller;
  final PlacedRoomItem? selectedItem;
  final RoomItemDefinition? selectedDefinition;
  final VoidCallback onClose;
  final VoidCallback onOpenShop;
  final ValueChanged<String> onAddOwnedItem;
  final VoidCallback? onRotateSelected;
  final VoidCallback? onStoreSelected;
  final SkyWeather skyWeather;
  final double? skyTimeOfDay;
  final double cameraZoom;
  final double cameraRotateSensitivity;
  final ValueChanged<SkyWeather> onSkyWeather;
  final ValueChanged<double?> onSkyTimeOfDay;
  final ValueChanged<double> onCameraZoom;
  final ValueChanged<double> onCameraRotateSensitivity;

  static const List<({String label, double? value})> _skyTimes = [
    (label: 'Live', value: null),
    (label: 'Dawn', value: 0.26),
    (label: 'Day', value: 0.5),
    (label: 'Dusk', value: 0.73),
    (label: 'Night', value: 0.95),
  ];

  String _weatherLabel(SkyWeather w) => switch (w) {
    SkyWeather.clear => 'Clear',
    SkyWeather.cloudy => 'Cloudy',
    SkyWeather.overcast => 'Overcast',
    SkyWeather.rain => 'Rain',
  };

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          height: height,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Room settings',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Inventory, placement controls, and quick actions.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: onOpenShop,
                      icon: const Icon(Icons.shopping_bag_rounded),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: onClose,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    InfoPill(
                      icon: Icons.favorite_rounded,
                      label: 'Likes',
                      value: '${controller.likesBalance}',
                      tint: const Color(0xFFF6E2CF),
                    ),
                    InfoPill(
                      icon: Icons.aspect_ratio_rounded,
                      label: 'Room size',
                      value:
                          '${RoomEditorController.roomWidth} x ${RoomEditorController.roomDepth}',
                      tint: const Color(0xFFF1E9DC),
                    ),
                    InfoPill(
                      icon: Icons.chair_alt_rounded,
                      label: 'Placed',
                      value: '${controller.placedItems.length}',
                      tint: const Color(0xFFE7E1D6),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Sky',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Weather and time of day shown through the window.',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final w in SkyWeather.values)
                      ChoiceChip(
                        label: Text(_weatherLabel(w)),
                        selected: skyWeather == w,
                        onSelected: (_) => onSkyWeather(w),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final t in _skyTimes)
                      ChoiceChip(
                        label: Text(t.label),
                        selected: skyTimeOfDay == t.value,
                        onSelected: (_) => onSkyTimeOfDay(t.value),
                      ),
                  ],
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
                  min: 0.4,
                  max: 1.8,
                  divisions: 14,
                  onChanged: onCameraRotateSensitivity,
                ),
                const SizedBox(height: 18),
                Text(
                  selectedDefinition == null
                      ? 'Selection'
                      : selectedDefinition!.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SoftCard(
                      color: const Color(0xFFFFF7EF),
                      padding: const EdgeInsets.all(16),
                      child: selectedItem == null
                          ? const _EmptySelection()
                          : _SelectionPanel(
                              item: selectedItem!,
                              definition: selectedDefinition!,
                              onRotate: onRotateSelected!,
                              onStore: onStoreSelected!,
                            ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Owned pieces',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Add owned items directly into the room from here.',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final definition in controller.ownedCatalog) ...[
                            SizedBox(
                              width: 168,
                              child: _InventoryCard(
                                definition: definition,
                                availableCount: controller.availableToPlace(
                                  definition.id,
                                ),
                                ownedCount: controller.ownedCount(
                                  definition.id,
                                ),
                                onAdd:
                                    controller.availableToPlace(definition.id) >
                                        0
                                    ? () => onAddOwnedItem(definition.id)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                        ],
                      ),
                    ),
                  ],
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

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.definition,
    required this.availableCount,
    required this.ownedCount,
    this.onAdd,
  });

  final RoomItemDefinition definition;
  final int availableCount;
  final int ownedCount;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SoftCard(
      padding: const EdgeInsets.all(14),
      color: Colors.white.withValues(alpha: 0.9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 72,
            width: double.infinity,
            decoration: BoxDecoration(
              color: definition.tint.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: RoomSpriteThumbnail(definition: definition, size: 68),
            ),
          ),
          const SizedBox(height: 12),
          Text(definition.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '$ownedCount owned • $availableCount ready',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: onAdd,
              child: Text(availableCount > 0 ? 'Add' : 'All placed'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionPanel extends StatelessWidget {
  const _SelectionPanel({
    required this.item,
    required this.definition,
    required this.onRotate,
    required this.onStore,
  });

  final PlacedRoomItem item;
  final RoomItemDefinition definition;
  final VoidCallback onRotate;
  final VoidCallback onStore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 88,
              width: 88,
              decoration: BoxDecoration(
                color: definition.tint.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: RoomSpriteThumbnail(
                  definition: definition,
                  quarterTurns: item.rotationQuarterTurns,
                  size: 80,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  TopicChip(
                    label:
                        'Position ${item.origin.x.toStringAsFixed(1)}, ${item.origin.z.toStringAsFixed(1)}',
                    icon: Icons.place_rounded,
                    highlight: true,
                  ),
                  TopicChip(
                    label:
                        'Rotation ${item.rotationDegrees.toStringAsFixed(0)}°',
                    icon: Icons.rotate_90_degrees_ccw_rounded,
                  ),
                  TopicChip(label: definition.typeLabel, icon: definition.icon),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onRotate,
                icon: const Icon(Icons.rotate_90_degrees_ccw_rounded),
                label: const Text('Rotate'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: onStore,
                icon: const Icon(Icons.inventory_2_rounded),
                label: const Text('Store'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptySelection extends StatelessWidget {
  const _EmptySelection();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.touch_app_rounded, color: AppColors.clay),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Select a furniture piece in the room to rotate it or return it to inventory.',
            style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}
