import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

import 'room_state.dart';

class IsometricRoomView extends StatefulWidget {
  const IsometricRoomView({super.key, required this.controller});

  final RoomEditorController controller;

  @override
  State<IsometricRoomView> createState() => _IsometricRoomViewState();
}

class _IsometricRoomViewState extends State<IsometricRoomView> {
  late final three.ThreeJS _threeJs;
  late final three.PerspectiveCamera _camera;

  final Map<String, _SceneFurniture> _sceneFurniture = {};
  final three.Raycaster _raycaster = three.Raycaster();
  final three.Vector2 _pointer = three.Vector2.zero();
  final three.Plane _dragPlane = three.Plane();
  final three.Vector3 _dragIntersection = three.Vector3.zero();
  final three.Vector3 _dragOffset = three.Vector3.zero();

  bool _sceneReady = false;
  bool _threeConfigured = false;
  bool _pointerEventsAttached = false;
  String? _activeDragItemId;
  GridPoint? _dragPreviewOrigin;
  bool _dragPreviewValid = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _threeJs = three.ThreeJS(
      settings: three.Settings(
        useSourceTexture: true,
        antialias: true,
        alpha: true,
        clearColor: 0x090807,
        clearAlpha: 1,
      ),
      setup: _setupScene,
      onSetupComplete: _handleSetupComplete,
      windowResizeUpdate: _handleResize,
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    if (_threeConfigured) {
      _detachPointerEvents();
      _threeJs.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF191513), Color(0xFF0D0B0A)],
        ),
      ),
      child: _threeJs.build(),
    );
  }

  Future<void> _setupScene() async {
    _camera = three.PerspectiveCamera(
      42,
      _threeJs.width / _threeJs.height,
      0.1,
      80,
    );
    _threeJs.camera = _camera;
    _threeJs.scene = three.Scene();
    _threeConfigured = true;

    _dragPlane.setFromNormalAndCoplanarPoint(
      three.Vector3(0, 1, 0),
      three.Vector3.zero(),
    );

    _configureCamera(Size(_threeJs.width, _threeJs.height));
    _buildRoomShell();
    _attachPointerEvents();
    _syncSceneWithController();
  }

  void _handleSetupComplete() {
    _sceneReady = true;
    _syncSceneWithController();
    if (mounted) {
      setState(() {});
    }
  }

  void _handleControllerChanged() {
    if (_sceneReady) {
      _syncSceneWithController();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _handleResize(Size size) {
    _configureCamera(size);
  }

  void _configureCamera(Size size) {
    _camera.aspect = size.width / size.height;
    _camera.near = 0.1;
    _camera.far = 80;
    _camera.position.setValues(0.0, 2.55, 8.8);
    _camera.lookAt(three.Vector3(0, 1.55, 0.2));
    _camera.updateProjectionMatrix();
  }

  void _buildRoomShell() {
    final roomWidth =
        RoomEditorController.roomWidth * RoomEditorController.cellSize;
    final roomDepth =
        RoomEditorController.roomDepth * RoomEditorController.cellSize;

    final ambient = three.AmbientLight(0xf3e7d7, 1.0);
    _threeJs.scene.add(ambient);

    final hemi = three.HemisphereLight(0xf7eadc, 0x2e221c, 1.1);
    hemi.position.setValues(0, 10, 0);
    _threeJs.scene.add(hemi);

    final keyLight = three.DirectionalLight(0xffebd2, 1.0);
    keyLight.position.setValues(0, 6, 8);
    _threeJs.scene.add(keyLight);

    final warmLamp = three.PointLight(0xf9c8a9, 1.5, 14, 2);
    warmLamp.position.setValues(2.4, 3.7, -0.8);
    _threeJs.scene.add(warmLamp);

    final platform = _box(
      width: roomWidth + 1.4,
      height: 0.36,
      depth: roomDepth + 1.2,
      color: const Color(0xFF4A342B),
      receiveShadow: true,
    )..position.setValues(0, -0.26, 0.3);
    _threeJs.scene.add(platform);

    final floor = _box(
      width: roomWidth,
      height: 0.12,
      depth: roomDepth,
      color: const Color(0xFF6A4E41),
      receiveShadow: true,
    )..position.setValues(0, -0.04, 0);
    _threeJs.scene.add(floor);

    for (var x = 0; x < RoomEditorController.roomWidth; x += 1) {
      final plank = _box(
        width: 0.9,
        height: 0.02,
        depth: roomDepth - 0.08,
        color: x.isEven ? const Color(0xFF785848) : const Color(0xFF6C5143),
        receiveShadow: true,
      )..position.setValues(-roomWidth / 2 + 0.5 + x.toDouble(), 0.03, 0);
      _threeJs.scene.add(plank);
    }

    final backWall = _box(
      width: roomWidth,
      height: 5.0,
      depth: 0.22,
      color: const Color(0xFFEEE7DE),
      receiveShadow: true,
    )..position.setValues(0, 2.4, -roomDepth / 2 + 0.1);
    _threeJs.scene.add(backWall);

    final leftWall = _box(
      width: 0.22,
      height: 5.0,
      depth: roomDepth,
      color: const Color(0xFFD8CEC3),
      receiveShadow: true,
    )..position.setValues(-roomWidth / 2 + 0.1, 2.4, 0);
    _threeJs.scene.add(leftWall);

    final rightWall = _box(
      width: 0.22,
      height: 5.0,
      depth: roomDepth,
      color: const Color(0xFFD3C9BE),
      receiveShadow: true,
    )..position.setValues(roomWidth / 2 - 0.1, 2.4, 0);
    _threeJs.scene.add(rightWall);

    final ceilingBeam = _box(
      width: roomWidth + 0.5,
      height: 0.18,
      depth: 0.4,
      color: const Color(0xFF3A2A24),
    )..position.setValues(0, 4.6, 0.45);
    _threeJs.scene.add(ceilingBeam);

    final rearWindowFrame = _box(
      width: 4.9,
      height: 2.7,
      depth: 0.1,
      color: const Color(0xFF4C392F),
    )..position.setValues(1.0, 2.35, -roomDepth / 2 + 0.18);
    _threeJs.scene.add(rearWindowFrame);

    final rearWindowGlass =
        three.Mesh(
            three.BoxGeometry(4.45, 2.25, 0.04),
            three.MeshPhongMaterial.fromMap({
              'color': _hex(const Color(0xFF131211)),
              'transparent': true,
              'opacity': 0.92,
            }),
          )
          ..position.setValues(1.0, 2.28, -roomDepth / 2 + 0.22)
          ..receiveShadow = true;
    _threeJs.scene.add(rearWindowGlass);

    final mullion = _box(
      width: 0.12,
      height: 2.25,
      depth: 0.08,
      color: const Color(0xFF5B463B),
    )..position.setValues(1.0, 2.28, -roomDepth / 2 + 0.24);
    _threeJs.scene.add(mullion);

    final windowSeat = _box(
      width: 5.1,
      height: 0.34,
      depth: 1.1,
      color: const Color(0xFF5C4337),
      receiveShadow: true,
    )..position.setValues(1.0, 0.7, -roomDepth / 2 + 0.58);
    _threeJs.scene.add(windowSeat);

    final windowSeatBase = _box(
      width: 5.2,
      height: 0.78,
      depth: 1.04,
      color: const Color(0xFFC7B6A6),
      receiveShadow: true,
    )..position.setValues(1.0, 0.25, -roomDepth / 2 + 0.6);
    _threeJs.scene.add(windowSeatBase);

    final laptopBase = _box(
      width: 0.64,
      height: 0.05,
      depth: 0.42,
      color: const Color(0xFFD3CBC4),
    )..position.setValues(2.55, 0.9, -roomDepth / 2 + 0.38);
    _threeJs.scene.add(laptopBase);

    final laptopScreen =
        _box(
            width: 0.62,
            height: 0.4,
            depth: 0.04,
            color: const Color(0xFF272324),
          )
          ..position.setValues(2.55, 1.12, -roomDepth / 2 + 0.29)
          ..rotation.x = -0.35;
    _threeJs.scene.add(laptopScreen);

    final screenGlow = _box(
      width: 0.5,
      height: 0.28,
      depth: 0.01,
      color: const Color(0xFFB8705C),
    )..position.setValues(2.55, 1.12, -roomDepth / 2 + 0.26);
    _threeJs.scene.add(screenGlow);

    final frame = _box(
      width: 0.55,
      height: 0.82,
      depth: 0.06,
      color: const Color(0xFFD4D0CB),
    )..position.setValues(0.7, 1.18, -roomDepth / 2 + 0.43);
    _threeJs.scene.add(frame);

    final candle =
        three.Mesh(
            three.CylinderGeometry(0.09, 0.09, 0.16, 14),
            three.MeshPhongMaterial.fromMap({
              'color': _hex(const Color(0xFFE5DFD8)),
            }),
          )
          ..position.setValues(1.45, 0.92, -roomDepth / 2 + 0.38)
          ..castShadow = true;
    _threeJs.scene.add(candle);

    final pendantStem = _box(
      width: 0.05,
      height: 0.82,
      depth: 0.05,
      color: const Color(0xFF1D1715),
    )..position.setValues(2.4, 4.15, -0.9);
    _threeJs.scene.add(pendantStem);

    final pendant =
        three.Mesh(
            three.SphereGeometry(0.3, 18, 18),
            three.MeshPhongMaterial.fromMap({
              'color': _hex(const Color(0xFFF7D6C8)),
              'emissive': 0xf0b89e,
              'emissiveIntensity': 0.3,
            }),
          )
          ..position.setValues(2.4, 3.55, -0.9)
          ..castShadow = true;
    _threeJs.scene.add(pendant);
  }

  void _attachPointerEvents() {
    if (_pointerEventsAttached) {
      return;
    }

    final dom = _threeJs.domElement;
    dom.addEventListener(three.PeripheralType.pointerdown, _onPointerDown);
    dom.addEventListener(three.PeripheralType.pointermove, _onPointerMove);
    dom.addEventListener(three.PeripheralType.pointerup, _onPointerUp);
    dom.addEventListener(three.PeripheralType.pointercancel, _onPointerUp);
    dom.addEventListener(three.PeripheralType.pointerleave, _onPointerUp);
    _pointerEventsAttached = true;
  }

  void _detachPointerEvents() {
    if (!_pointerEventsAttached || !_sceneReady) {
      return;
    }

    final dom = _threeJs.domElement;
    dom.removeEventListener(three.PeripheralType.pointerdown, _onPointerDown);
    dom.removeEventListener(three.PeripheralType.pointermove, _onPointerMove);
    dom.removeEventListener(three.PeripheralType.pointerup, _onPointerUp);
    dom.removeEventListener(three.PeripheralType.pointercancel, _onPointerUp);
    dom.removeEventListener(three.PeripheralType.pointerleave, _onPointerUp);
    _pointerEventsAttached = false;
  }

  void _onPointerDown(dynamic event) {
    _updatePointer(event);
    _raycaster.setFromCamera(_pointer, _camera);
    final intersections = _raycaster.intersectObjects(
      _sceneFurniture.values.map((item) => item.root).toList(),
      true,
    );

    if (intersections.isEmpty) {
      widget.controller.selectItem(null);
      return;
    }

    final hit = intersections.first.object;
    final sceneFurniture = _resolveSceneFurniture(hit);
    if (sceneFurniture == null) {
      widget.controller.selectItem(null);
      return;
    }

    widget.controller.selectItem(sceneFurniture.itemId);
    _activeDragItemId = sceneFurniture.itemId;
    _dragPreviewValid = true;

    if (_raycaster.ray.intersectPlane(_dragPlane, _dragIntersection) != null) {
      _dragOffset
        ..setFrom(_dragIntersection)
        ..sub(sceneFurniture.root.position);
    }

    _syncSceneWithController();
  }

  void _onPointerMove(dynamic event) {
    if (_activeDragItemId == null) {
      return;
    }

    final placed = widget.controller.placedItemById(_activeDragItemId!);
    if (placed == null) {
      return;
    }

    _updatePointer(event);
    _raycaster.setFromCamera(_pointer, _camera);

    if (_raycaster.ray.intersectPlane(_dragPlane, _dragIntersection) == null) {
      return;
    }

    final draggedWorld = _dragIntersection.clone()..sub(_dragOffset);
    final previewOrigin = _worldToGridOrigin(
      definitionId: placed.definitionId,
      quarterTurns: placed.rotationQuarterTurns,
      x: draggedWorld.x,
      z: draggedWorld.z,
    );

    _dragPreviewOrigin = previewOrigin;
    _dragPreviewValid = widget.controller.canOccupy(
      definitionId: placed.definitionId,
      origin: previewOrigin,
      rotationQuarterTurns: placed.rotationQuarterTurns,
      ignoringInstanceId: placed.instanceId,
    );
    _syncSceneWithController();
  }

  void _onPointerUp([dynamic _]) {
    if (_activeDragItemId == null) {
      return;
    }

    if (_dragPreviewOrigin != null && _dragPreviewValid) {
      widget.controller.movePlacedItem(_activeDragItemId!, _dragPreviewOrigin!);
    }

    _activeDragItemId = null;
    _dragPreviewOrigin = null;
    _dragPreviewValid = true;
    _syncSceneWithController();
  }

  void _syncSceneWithController() {
    if (!_sceneReady) {
      return;
    }

    final currentIds = widget.controller.placedItems
        .map((item) => item.instanceId)
        .toSet();
    final sceneIds = _sceneFurniture.keys.toList();

    for (final instanceId in sceneIds) {
      if (!currentIds.contains(instanceId)) {
        final removed = _sceneFurniture.remove(instanceId);
        if (removed != null) {
          _threeJs.scene.remove(removed.root);
        }
      }
    }

    for (final item in widget.controller.placedItems) {
      _sceneFurniture.putIfAbsent(
        item.instanceId,
        () => _createSceneFurniture(item),
      );
    }

    for (final item in widget.controller.placedItems) {
      final isDragging = item.instanceId == _activeDragItemId;
      final previewOrigin = isDragging ? _dragPreviewOrigin : null;
      _updateSceneFurniture(
        item,
        previewOrigin: previewOrigin,
        isDragging: isDragging,
        isValid: isDragging ? _dragPreviewValid : true,
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  _SceneFurniture _createSceneFurniture(PlacedRoomItem item) {
    final definition = widget.controller.definitionFor(item.definitionId);
    final footprint = definition.footprintForRotation(0);

    final root = three.Group()..userData['itemId'] = item.instanceId;
    final selectionMaterial = three.MeshBasicMaterial.fromMap({
      'color': 0xffffff,
      'transparent': true,
      'opacity': 0.0,
      'depthWrite': false,
    });
    final selectionPlate =
        three.Mesh(
            three.BoxGeometry(
              footprint.width * RoomEditorController.cellSize * 0.9,
              0.05,
              footprint.depth * RoomEditorController.cellSize * 0.9,
            ),
            selectionMaterial,
          )
          ..position.y = 0.03
          ..renderOrder = 8;
    root.add(selectionPlate);
    root.add(_buildFurnitureVisual(definition));
    _threeJs.scene.add(root);

    return _SceneFurniture(
      itemId: item.instanceId,
      root: root,
      selectionMaterial: selectionMaterial,
    );
  }

  void _updateSceneFurniture(
    PlacedRoomItem item, {
    GridPoint? previewOrigin,
    required bool isDragging,
    required bool isValid,
  }) {
    final sceneFurniture = _sceneFurniture[item.instanceId];
    if (sceneFurniture == null) {
      return;
    }

    final activeOrigin = previewOrigin ?? item.origin;
    final position = _gridOriginToWorld(
      definitionId: item.definitionId,
      quarterTurns: item.rotationQuarterTurns,
      origin: activeOrigin,
    );

    sceneFurniture.root.position.setValues(
      position.x,
      isDragging ? 0.14 : 0,
      position.z,
    );
    sceneFurniture.root.rotation.y = item.rotationQuarterTurns * math.pi / 2;

    final isSelected =
        widget.controller.selectedItemId == item.instanceId || isDragging;
    sceneFurniture.selectionMaterial.color = three.Color.fromHex32(
      isValid ? (isSelected ? 0xe5b892 : 0xffffff) : 0xd76b60,
    );
    sceneFurniture.selectionMaterial.opacity = isValid
        ? (isSelected ? 0.4 : 0.0)
        : 0.58;
    sceneFurniture.root.scale.setValues(
      isDragging ? 1.03 : 1.0,
      isDragging ? 1.03 : 1.0,
      isDragging ? 1.03 : 1.0,
    );
  }

  _SceneFurniture? _resolveSceneFurniture(three.Object3D? object) {
    var current = object;
    while (current != null) {
      final value = current.userData['itemId'];
      if (value is String) {
        return _sceneFurniture[value];
      }
      current = current.parent;
    }
    return null;
  }

  void _updatePointer(dynamic event) {
    final box =
        _threeJs.globalKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }

    final width = box.size.width;
    final height = box.size.height;
    _pointer.x = (event.clientX as double) / width * 2 - 1;
    _pointer.y = -(event.clientY as double) / height * 2 + 1;
  }

  GridPoint _worldToGridOrigin({
    required String definitionId,
    required int quarterTurns,
    required double x,
    required double z,
  }) {
    final footprint = widget.controller.footprintForDefinition(
      definitionId,
      quarterTurns,
    );
    final roomWidth =
        RoomEditorController.roomWidth * RoomEditorController.cellSize;
    final roomDepth =
        RoomEditorController.roomDepth * RoomEditorController.cellSize;

    final snappedX =
        ((x + roomWidth / 2 - footprint.width / 2) /
                RoomEditorController.cellSize)
            .round();
    final snappedZ =
        ((z + roomDepth / 2 - footprint.depth / 2) /
                RoomEditorController.cellSize)
            .round();

    return widget.controller.clampOrigin(
      definitionId,
      quarterTurns,
      GridPoint(snappedX, snappedZ),
    );
  }

  three.Vector3 _gridOriginToWorld({
    required String definitionId,
    required int quarterTurns,
    required GridPoint origin,
  }) {
    final footprint = widget.controller.footprintForDefinition(
      definitionId,
      quarterTurns,
    );
    final roomWidth =
        RoomEditorController.roomWidth * RoomEditorController.cellSize;
    final roomDepth =
        RoomEditorController.roomDepth * RoomEditorController.cellSize;

    final x = -roomWidth / 2 + origin.x + footprint.width / 2;
    final z = -roomDepth / 2 + origin.z + footprint.depth / 2;
    return three.Vector3(x, 0, z);
  }

  three.Group _buildFurnitureVisual(RoomItemDefinition definition) {
    switch (definition.visualKind) {
      case RoomItemVisualKind.bed:
        return _buildBed();
      case RoomItemVisualKind.nightstand:
        return _buildNightstand();
      case RoomItemVisualKind.wardrobe:
        return _buildWardrobe();
      case RoomItemVisualKind.vanity:
        return _buildVanity();
      case RoomItemVisualKind.ottoman:
        return _buildOttoman();
      case RoomItemVisualKind.floorLamp:
        return _buildFloorLamp();
      case RoomItemVisualKind.plant:
        return _buildPlant();
    }
  }

  three.Group _buildBed() {
    final group = three.Group();
    group.add(
      _box(
        width: 2.7,
        height: 0.42,
        depth: 3.6,
        color: const Color(0xFFE7E0D7),
        y: 0.22,
      ),
    );
    group.add(
      _box(
        width: 2.76,
        height: 1.02,
        depth: 0.18,
        color: const Color(0xFFDDDDD8),
        y: 0.72,
        z: -1.68,
      ),
    );
    group.add(
      _box(
        width: 2.56,
        height: 0.18,
        depth: 3.0,
        color: const Color(0xFFD2D0CC),
        y: 0.54,
      ),
    );
    group.add(
      _box(
        width: 2.54,
        height: 0.2,
        depth: 3.0,
        color: const Color(0xFFDDD8D2),
        y: 0.78,
      ),
    );
    group.add(
      _box(
        width: 2.34,
        height: 0.16,
        depth: 2.82,
        color: const Color(0xFFECE8E2),
        y: 0.91,
      ),
    );
    group.add(
      _box(
        width: 0.86,
        height: 0.18,
        depth: 0.58,
        color: const Color(0xFFF8F2EB),
        y: 1.05,
        x: -0.48,
        z: -1.18,
      ),
    );
    group.add(
      _box(
        width: 0.86,
        height: 0.18,
        depth: 0.58,
        color: const Color(0xFFF8F2EB),
        y: 1.05,
        x: 0.48,
        z: -1.18,
      ),
    );
    return group;
  }

  three.Group _buildNightstand() {
    final group = three.Group();
    group.add(
      _box(
        width: 0.82,
        height: 0.72,
        depth: 0.82,
        color: const Color(0xFF8A6957),
        y: 0.36,
      ),
    );
    group.add(
      _box(
        width: 0.82,
        height: 0.08,
        depth: 0.82,
        color: const Color(0xFFE8DDCF),
        y: 0.78,
      ),
    );
    return group;
  }

  three.Group _buildWardrobe() {
    final group = three.Group();
    group.add(
      _box(
        width: 1.72,
        height: 2.88,
        depth: 0.78,
        color: const Color(0xFFD7C9B7),
        y: 1.44,
      ),
    );
    group.add(
      _box(
        width: 0.08,
        height: 2.6,
        depth: 0.8,
        color: const Color(0xFF41332E),
        x: -0.86,
        y: 1.3,
      ),
    );
    group.add(
      _box(
        width: 0.08,
        height: 2.6,
        depth: 0.8,
        color: const Color(0xFF41332E),
        x: 0.86,
        y: 1.3,
      ),
    );
    return group;
  }

  three.Group _buildVanity() {
    final group = three.Group();
    group.add(
      _box(
        width: 1.9,
        height: 0.14,
        depth: 0.74,
        color: const Color(0xFF6A4B3E),
        y: 0.72,
      ),
    );
    for (final x in const [-0.78, 0.78]) {
      for (final z in const [-0.26, 0.26]) {
        group.add(
          _box(
            width: 0.08,
            height: 0.72,
            depth: 0.08,
            color: const Color(0xFFE9E1D7),
            x: x,
            y: 0.36,
            z: z,
          ),
        );
      }
    }
    group.add(
      _box(
        width: 0.82,
        height: 1.0,
        depth: 0.08,
        color: const Color(0xFFE1E5EC),
        y: 1.34,
        z: -0.3,
      ),
    );
    return group;
  }

  three.Group _buildOttoman() {
    final group = three.Group();
    group.add(
      _box(
        width: 0.72,
        height: 0.48,
        depth: 0.72,
        color: const Color(0xFF8A7A68),
        y: 0.24,
      ),
    );
    group.add(
      _box(
        width: 0.64,
        height: 0.12,
        depth: 0.64,
        color: const Color(0xFFD8BBAF),
        y: 0.54,
      ),
    );
    return group;
  }

  three.Group _buildFloorLamp() {
    final group = three.Group();
    group.add(
      _box(
        width: 0.12,
        height: 1.48,
        depth: 0.12,
        color: const Color(0xFF22211F),
        y: 0.74,
      ),
    );
    group.add(
      _box(
        width: 0.38,
        height: 0.04,
        depth: 0.38,
        color: const Color(0xFF262321),
        y: 0.03,
      ),
    );
    group.add(
      _box(
        width: 0.56,
        height: 0.46,
        depth: 0.56,
        color: const Color(0xFFF2D7BC),
        y: 1.58,
      ),
    );
    return group;
  }

  three.Group _buildPlant() {
    final group = three.Group();
    final pot =
        three.Mesh(
            three.CylinderGeometry(0.18, 0.16, 0.28, 14),
            three.MeshPhongMaterial.fromMap({
              'color': _hex(const Color(0xFFB77E58)),
            }),
          )
          ..position.setValues(0, 0.14, 0)
          ..castShadow = true;
    group.add(pot);

    group.add(_leaf(-0.12, 0.58, 0.02, 0.18));
    group.add(_leaf(0.12, 0.60, -0.02, 0.20));
    group.add(_leaf(0.00, 0.72, 0.04, 0.22));
    return group;
  }

  three.Mesh _leaf(double x, double y, double z, double radius) {
    return three.Mesh(
        three.SphereGeometry(radius, 14, 14),
        three.MeshPhongMaterial.fromMap({
          'color': _hex(const Color(0xFF748F63)),
        }),
      )
      ..position.setValues(x, y, z)
      ..castShadow = true;
  }

  three.Mesh _box({
    required double width,
    required double height,
    required double depth,
    required Color color,
    double x = 0,
    double y = 0,
    double z = 0,
    bool castShadow = true,
    bool receiveShadow = false,
  }) {
    return three.Mesh(
        three.BoxGeometry(width, height, depth),
        three.MeshPhongMaterial.fromMap({'color': _hex(color)}),
      )
      ..position.setValues(x, y, z)
      ..castShadow = castShadow
      ..receiveShadow = receiveShadow;
  }

  int _hex(Color color) => color.toARGB32() & 0x00ffffff;
}

class _SceneFurniture {
  const _SceneFurniture({
    required this.itemId,
    required this.root,
    required this.selectionMaterial,
  });

  final String itemId;
  final three.Group root;
  final three.MeshBasicMaterial selectionMaterial;
}
