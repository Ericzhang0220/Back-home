import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

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
  });

  final RoomEditorController controller;
  final VoidCallback onOpenShop;
  final bool isActive;
  final bool isChromeVisible;
  final bool isChromeInteractive;
  final VoidCallback onRevealChrome;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  bool _panelOpen = false;
  bool _deskFocused = false;
  bool _nightMode = false;

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
    setState(() {
      _deskFocused = true;
      _nightMode = false;
      _panelOpen = false;
    });
  }

  void _openNightMode() {
    setState(() {
      _deskFocused = false;
      _nightMode = true;
      _panelOpen = false;
    });
  }

  void _restoreRoomLight() {
    setState(() {
      _nightMode = false;
      _deskFocused = false;
    });
    widget.onRevealChrome();
  }

  void _handleDoubleTap() {
    if (_nightMode) {
      _restoreRoomLight();
      return;
    }
    setState(() {
      _deskFocused = false;
    });
    widget.onRevealChrome();
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 180) {
      widget.onRevealChrome();
    }
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
          onHorizontalDragEnd: _handleHorizontalDragEnd,
          child: Stack(
            children: [
              Positioned.fill(
                child: _PhotoRoomScene(
                  deskFocused: _deskFocused,
                  nightMode: _nightMode,
                  onTapDesk: _focusDesk,
                  onTapBed: _openNightMode,
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
                        duration: const Duration(seconds: 2),
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
                    child: const _GoodNightOverlay(),
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

class _PhotoRoomScene extends StatelessWidget {
  const _PhotoRoomScene({
    required this.deskFocused,
    required this.nightMode,
    required this.onTapDesk,
    required this.onTapBed,
  });

  final bool deskFocused;
  final bool nightMode;
  final VoidCallback onTapDesk;
  final VoidCallback onTapBed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final scale = deskFocused ? 2.15 : 1.0;
        final offset = deskFocused
            ? Offset(-size.width * 0.12, size.height * 0.11)
            : Offset.zero;

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSlide(
                duration: const Duration(milliseconds: 760),
                curve: Curves.easeInOutCubic,
                offset: Offset(offset.dx / size.width, offset.dy / size.height),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 760),
                  curve: Curves.easeInOutCubic,
                  scale: scale,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/room/room_start.png',
                        key: const ValueKey('room-start-background'),
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        filterQuality: FilterQuality.high,
                      ),
                      if (deskFocused) const _DeskAccessories(),
                    ],
                  ),
                ),
              ),
              if (!deskFocused && !nightMode) ...[
                _RoomHotspot(
                  left: size.width * 0.08,
                  top: size.height * 0.29,
                  width: size.width * 0.9,
                  height: size.height * 0.24,
                  onTap: onTapDesk,
                ),
                _RoomHotspot(
                  left: 0,
                  top: size.height * 0.54,
                  width: size.width * 0.94,
                  height: size.height * 0.35,
                  onTap: onTapBed,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RoomHotspot extends StatelessWidget {
  const _RoomHotspot({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          splashColor: Colors.white.withValues(alpha: 0.08),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _DeskAccessories extends StatelessWidget {
  const _DeskAccessories();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return Stack(
          children: [
            Positioned(
              left: width * 0.26,
              top: height * 0.39,
              child: const _PenCup(),
            ),
            Positioned(
              left: width * 0.5,
              top: height * 0.405,
              child: const _SoftRadio(),
            ),
            Positioned(
              left: width * 0.66,
              top: height * 0.41,
              child: const _DeskTray(),
            ),
          ],
        );
      },
    );
  }
}

class _PenCup extends StatelessWidget {
  const _PenCup();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 78,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            top: 2,
            left: 16,
            child: Transform.rotate(
              angle: -0.18,
              child: Container(
                width: 5,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFB8775D),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 14,
            child: Transform.rotate(
              angle: 0.16,
              child: Container(
                width: 5,
                height: 47,
                decoration: BoxDecoration(
                  color: const Color(0xFF43524B),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          Container(
            width: 34,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFD9D8D1).withValues(alpha: 0.94),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(7),
                bottom: Radius.circular(11),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 10,
                  offset: Offset(0, 6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftRadio extends StatelessWidget {
  const _SoftRadio();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFF8FA092).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 10,
            top: 12,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFF53645C),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 14,
            child: Column(
              children: List.generate(
                3,
                (index) => Container(
                  margin: const EdgeInsets.only(bottom: 5),
                  width: 34,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7E3DA).withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeskTray extends StatelessWidget {
  const _DeskTray();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 42,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: Transform.rotate(
              angle: -0.05,
              child: Container(
                width: 76,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFC9B8A4),
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 8,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFE6E1D7),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoodNightOverlay extends StatelessWidget {
  const _GoodNightOverlay();

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xE9000000)),
      child: Stack(
        children: [
          Positioned(
            top: topPadding + 82,
            right: 52,
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
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Have a good night! See you tomorrow.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFF5F0E8),
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  Text(
                    '(Your room is now in night mode. If you want to go back, just double click the scene.)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFF5F0E8),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
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
                    const InfoPill(
                      icon: Icons.grid_4x4_rounded,
                      label: 'Layout',
                      value: '10 x 8',
                      tint: Color(0xFFF1E9DC),
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
                    label: 'Grid ${item.origin.x + 1}, ${item.origin.z + 1}',
                    icon: Icons.place_rounded,
                    highlight: true,
                  ),
                  TopicChip(
                    label: 'Rotation ${item.rotationQuarterTurns * 90}°',
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
