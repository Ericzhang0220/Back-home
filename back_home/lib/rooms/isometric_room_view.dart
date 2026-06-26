import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

import 'room_state.dart';

enum _RoomTapTarget { desk, bed }

class IsometricRoomView extends StatefulWidget {
  const IsometricRoomView({
    super.key,
    required this.controller,
    required this.isActive,
    this.deskFocused = false,
    this.nightMode = false,
    this.onTapDesk,
    this.onTapBed,
  });

  final RoomEditorController controller;
  final bool isActive;
  final bool deskFocused;
  final bool nightMode;
  final VoidCallback? onTapDesk;
  final VoidCallback? onTapBed;

  @override
  State<IsometricRoomView> createState() => _IsometricRoomViewState();
}

class _IsometricRoomViewState extends State<IsometricRoomView> {
  static const Duration _sceneWarmupDelay = Duration(milliseconds: 350);

  // --- Centered 360° free-look camera (main view) -------------------------
  // The main view stands in the middle of the room and turns a full 360°.
  // >>> Tweak these to change the feel of the centered camera <<<
  static const double _cameraTiltStartThreshold = 10; // px dead-zone before a drag becomes a turn
  static const double _yawSensitivity = 0.008; // radians turned per pixel dragged
  static const double _eyeHeight = 1.9; // camera height at the room centre
  static const double _lookPitch = -0.22; // vertical aim (negative = look slightly down)
  static const double _mainFov = 64; // field of view for the centred view
  static const double _focusFov = 42; // field of view in the desk/night focus views
  static const double _minFov = 26; // pinch-zoom field-of-view clamp (zoomed in)
  static const double _maxFov = 84; // pinch-zoom field-of-view clamp (zoomed out)

  three.ThreeJS? _threeJs;
  late final three.PerspectiveCamera _camera;

  final Map<String, _SceneFurniture> _sceneFurniture = {};
  final three.Raycaster _raycaster = three.Raycaster();
  final three.Vector2 _pointer = three.Vector2.zero();
  final three.Plane _dragPlane = three.Plane();
  final three.Vector3 _dragIntersection = three.Vector3.zero();
  final three.Vector3 _dragOffset = three.Vector3.zero();
  final List<three.Object3D> _roomTapTargets = [];

  Timer? _sceneStartTimer;
  bool _sceneReady = false;
  bool _sceneRequested = false;
  bool _threeConfigured = false;
  bool _pointerEventsAttached = false;
  String? _activeDragItemId;
  GridPoint? _dragPreviewOrigin;
  bool _dragPreviewValid = true;
  _RoomTapTarget? _pendingTapTarget;
  double _pointerDownX = 0;
  double _pointerDownY = 0;
  double _pointerLastX = 0;
  double _pointerLastY = 0;
  bool _cameraTiltCandidate = false;
  bool _cameraTiltActive = false;
  double _cameraYaw = 0; // horizontal look angle (radians); 0 = facing the far wall
  double _yawAtDragStart = 0;
  double _cameraTiltPointerStartX = 0;

  // Smooth camera motion + pinch zoom. The camera eases toward these targets
  // every frame instead of snapping; _zoom drives the field of view.
  final three.Vector3 _cameraTargetPos = three.Vector3.zero();
  final three.Vector3 _cameraTargetLook = three.Vector3.zero();
  final three.Vector3 _cameraCurrentLook = three.Vector3.zero();
  bool _cameraPosed = false;
  double _zoom = 1.0;
  final Set<int> _activePointers = <int>{};

  static const double _minZoom = 0.62;
  static const double _maxZoom = 2.4;
  static const double _zoomInStep = 1.06;
  static const double _zoomOutStep = 0.94;
  // Higher = snappier camera transitions (eases ~this fraction per second).
  static const double _cameraLerpSpeed = 7.0;

  bool get _isPinching => _activePointers.length >= 2;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _scheduleSceneBootstrap();
      });
    }
  }

  @override
  void didUpdateWidget(covariant IsometricRoomView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final focusChanged =
        widget.deskFocused != oldWidget.deskFocused ||
        widget.nightMode != oldWidget.nightMode;
    if (focusChanged && _threeConfigured && _threeJs != null) {
      // Each view has its own designed framing, so start fresh from there.
      _zoom = 1.0;
      final width = _threeJs!.width <= 0 ? 1.0 : _threeJs!.width;
      final height = _threeJs!.height <= 0 ? 1.0 : _threeJs!.height;
      _configureCamera(Size(width, height));
    }

    if (widget.isActive == oldWidget.isActive) {
      return;
    }

    _syncSceneVisibility();

    if (widget.isActive) {
      if (!_sceneRequested) {
        _scheduleSceneBootstrap();
      }
      return;
    }

    if (!_sceneReady) {
      _sceneStartTimer?.cancel();
      _sceneStartTimer = null;
    }
  }

  @override
  void dispose() {
    _sceneStartTimer?.cancel();
    widget.controller.removeListener(_handleControllerChanged);
    if (_threeConfigured && _threeJs != null) {
      _detachPointerEvents();
      _threeJs!.dispose();
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_sceneRequested && _threeJs != null) _threeJs!.build(),
          IgnorePointer(
            ignoring: _sceneReady,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              opacity: _sceneReady ? 0 : 1,
              child: const _RoomScenePlaceholder(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setupScene() async {
    final threeJs = _threeJs;
    if (threeJs == null) {
      return;
    }

    final initialWidth = threeJs.width <= 0 ? 1.0 : threeJs.width;
    final initialHeight = threeJs.height <= 0 ? 1.0 : threeJs.height;
    _camera = three.PerspectiveCamera(
      42,
      initialWidth / initialHeight,
      0.1,
      80,
    );
    threeJs.camera = _camera;
    threeJs.scene = three.Scene();
    _threeConfigured = true;

    _dragPlane.setFromNormalAndCoplanarPoint(
      three.Vector3(0, 1, 0),
      three.Vector3.zero(),
    );

    _configureCamera(Size(initialWidth, initialHeight));
    threeJs.addAnimationEvent(_animateCamera);
    await _buildRoomShell();
    if (!mounted) {
      return;
    }
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
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    _configureCamera(size);
  }

  void _configureCamera(Size size) {
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;

    _camera.aspect = safeWidth / safeHeight;
    _camera.near = 0.1;
    _camera.far = 80;

    final roomDepth =
        RoomEditorController.roomDepth * RoomEditorController.cellSize;
    final farWallZ = -roomDepth / 2;

    final three.Vector3 basePos;
    final three.Vector3 lookAt;
    final double baseFov;
    if (widget.deskFocused) {
      // Fly to a close-up of the desk on the far wall.
      basePos = three.Vector3(1.0, 1.75, farWallZ + 3.6);
      lookAt = three.Vector3(1.0, 1.15, farWallZ + 0.4);
      baseFov = _focusFov;
    } else if (widget.nightMode) {
      // Turn toward the bed; the good-night overlay covers most of the frame.
      basePos = three.Vector3(0.0, 1.8, -0.6);
      lookAt = three.Vector3(-0.5, 0.85, -3.4);
      baseFov = _focusFov;
    } else {
      // Centred free-look: stand in the middle of the room and turn 360°.
      basePos = three.Vector3(0, _eyeHeight, 0);
      lookAt = three.Vector3(
        math.sin(_cameraYaw),
        _eyeHeight + _lookPitch,
        -math.cos(_cameraYaw),
      );
      baseFov = _mainFov;
    }

    // Pinch zoom narrows/widens the field of view, keeping the camera put.
    _camera.fov = (baseFov / _zoom).clamp(_minFov, _maxFov).toDouble();
    _camera.updateProjectionMatrix();

    _cameraTargetPos.setFrom(basePos);
    _cameraTargetLook.setFrom(lookAt);

    // First configuration snaps into place; later changes ease in (see
    // _animateCamera), so switching views glides instead of teleporting.
    if (!_cameraPosed) {
      _camera.position.setFrom(_cameraTargetPos);
      _cameraCurrentLook.setFrom(_cameraTargetLook);
      _camera.lookAt(_cameraCurrentLook);
      _cameraPosed = true;
    } else if (_cameraTiltActive) {
      // Look-around drag should track the finger directly rather than lagging
      // through the easing filter, so apply the new look immediately.
      _cameraCurrentLook.setFrom(_cameraTargetLook);
      _camera.lookAt(_cameraCurrentLook);
    }
  }

  void _animateCamera(double dt) {
    if (!_cameraPosed) {
      return;
    }
    // Nothing to do once the camera has settled on its target.
    if (_camera.position.distanceToSquared(_cameraTargetPos) < 1e-8 &&
        _cameraCurrentLook.distanceToSquared(_cameraTargetLook) < 1e-8) {
      return;
    }
    final t = (1 - math.exp(-dt * _cameraLerpSpeed)).clamp(0.0, 1.0).toDouble();
    _camera.position.lerp(_cameraTargetPos, t);
    _cameraCurrentLook.lerp(_cameraTargetLook, t);
    _camera.lookAt(_cameraCurrentLook);
  }

  void _onZoom(dynamic event) {
    final delta = (event.deltaY as num).toDouble();
    if (delta == 0) {
      return;
    }
    // Pinch apart (delta < 0) zooms in; pinch together (delta > 0) zooms out.
    final factor = delta < 0 ? _zoomInStep : _zoomOutStep;
    _zoom = (_zoom * factor).clamp(_minZoom, _maxZoom).toDouble();
    _refreshCamera();
  }

  void _cancelInteraction() {
    _activeDragItemId = null;
    _dragPreviewOrigin = null;
    _dragPreviewValid = true;
    _pendingTapTarget = null;
    _cameraTiltCandidate = false;
    _cameraTiltActive = false;
    _syncSceneWithController();
  }

  void _scheduleSceneBootstrap() {
    if (!widget.isActive || _sceneRequested || _sceneStartTimer != null) {
      return;
    }

    _sceneStartTimer = Timer(_sceneWarmupDelay, () {
      _sceneStartTimer = null;
      if (!mounted || _sceneRequested) {
        return;
      }

      final threeJs = three.ThreeJS(
        settings: three.Settings(
          antialias: true,
          alpha: true,
          clearColor: 0x090807,
          clearAlpha: 1,
        ),
        setup: _setupScene,
        onSetupComplete: _handleSetupComplete,
        windowResizeUpdate: _handleResize,
        loadingWidget: const SizedBox.shrink(),
      );
      threeJs.visible = widget.isActive;
      _threeJs = threeJs;

      setState(() {
        _sceneRequested = true;
      });
    });
  }

  Future<void> _buildRoomShell() async {
    final roomWidth =
        RoomEditorController.roomWidth * RoomEditorController.cellSize;
    final roomDepth =
        RoomEditorController.roomDepth * RoomEditorController.cellSize;
    final scene = _threeJs!.scene;

    final ambient = three.AmbientLight(0xe8d8c8, 0.3);
    scene.add(ambient);

    final hemi = three.HemisphereLight(0xf0deca, 0x2e221c, 0.44);
    hemi.position.setValues(0, 10, 0);
    scene.add(hemi);

    final keyLight = three.DirectionalLight(0xffead0, 1.18);
    keyLight.position.setValues(-3.4, 7.2, 5.8);
    keyLight.castShadow = true;
    keyLight.target!.position.setValues(0, 0.2, -2.5);
    keyLight.shadow!.mapSize.setValues(2048, 2048);
    keyLight.shadow!.bias = -0.0008;
    keyLight.shadow!.normalBias = 0.02;
    keyLight.shadow!.radius = 3;
    final shadowCamera = keyLight.shadow!.camera as three.OrthographicCamera;
    // Widened to cover the now-deeper room so shadows reach the far half.
    shadowCamera
      ..left = -10
      ..right = 10
      ..top = 11
      ..bottom = -11
      ..near = 0.5
      ..far = 34;
    shadowCamera.updateProjectionMatrix();
    scene.add(keyLight);
    scene.add(keyLight.target!);

    final warmLamp = three.PointLight(0xf3bea0, 0.72, 14, 2);
    warmLamp.position.setValues(2.4, 3.7, -0.8);
    scene.add(warmLamp);

    final platform = _box(
      width: roomWidth + 1.4,
      height: 0.36,
      depth: roomDepth + 1.2,
      color: const Color(0xFF453127),
      receiveShadow: true,
    )..position.setValues(0, -0.26, 0.3);
    scene.add(platform);

    final floor = _box(
      width: roomWidth,
      height: 0.12,
      depth: roomDepth,
      color: const Color(0xFF60483C),
      receiveShadow: true,
    )..position.setValues(0, -0.04, 0);
    scene.add(floor);

    for (var x = 0; x < RoomEditorController.roomWidth; x += 1) {
      final plank = _box(
        width: 0.9,
        height: 0.02,
        depth: roomDepth - 0.08,
        color: x.isEven ? const Color(0xFF6E5143) : const Color(0xFF5E463B),
        receiveShadow: true,
      )..position.setValues(-roomWidth / 2 + 0.5 + x.toDouble(), 0.03, 0);
      scene.add(plank);
    }

    await _yieldSceneStep();
    if (!mounted) {
      return;
    }

    final backWall = _box(
      width: roomWidth,
      height: 5.0,
      depth: 0.22,
      color: const Color(0xFFD4CCC2),
      receiveShadow: true,
    )..position.setValues(0, 2.4, -roomDepth / 2 + 0.1);
    scene.add(backWall);

    final leftWall = _box(
      width: 0.22,
      height: 5.0,
      depth: roomDepth,
      color: const Color(0xFFC8BDB2),
      receiveShadow: true,
    )..position.setValues(-roomWidth / 2 + 0.1, 2.4, 0);
    scene.add(leftWall);

    final rightWall = _box(
      width: 0.22,
      height: 5.0,
      depth: roomDepth,
      color: const Color(0xFFC1B5AA),
      receiveShadow: true,
    )..position.setValues(roomWidth / 2 - 0.1, 2.4, 0);
    scene.add(rightWall);

    // The near end used to be the open cutaway. Now the camera stands inside the
    // room, so close it off with a front wall and a ceiling for the 360° view.
    final frontWall = _box(
      width: roomWidth,
      height: 5.0,
      depth: 0.22,
      color: const Color(0xFFCBC0B5),
      receiveShadow: true,
    )..position.setValues(0, 2.4, roomDepth / 2 - 0.1);
    scene.add(frontWall);

    // castShadow:false so the ceiling does not block the key light's floor
    // shadows; its underside is still lit by ambient + the warm point lamp.
    final ceiling = _box(
      width: roomWidth,
      height: 0.2,
      depth: roomDepth,
      color: const Color(0xFF2B231F),
      castShadow: false,
      receiveShadow: false,
    )..position.setValues(0, 4.9, 0);
    scene.add(ceiling);

    _addSlopedCeilingDetails(scene, roomDepth);

    final ceilingBeam = _box(
      width: roomWidth + 0.5,
      height: 0.18,
      depth: 0.4,
      color: const Color(0xFF3A2A24),
    )..position.setValues(0, 4.6, 0.45);
    scene.add(ceilingBeam);

    await _yieldSceneStep();
    if (!mounted) {
      return;
    }

    final rearWindowFrame = _box(
      width: 4.9,
      height: 2.7,
      depth: 0.1,
      color: const Color(0xFF4C392F),
    )..position.setValues(1.0, 2.35, -roomDepth / 2 + 0.18);
    scene.add(rearWindowFrame);

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
    scene.add(rearWindowGlass);

    final mullion = _box(
      width: 0.12,
      height: 2.25,
      depth: 0.08,
      color: const Color(0xFF5B463B),
    )..position.setValues(1.0, 2.28, -roomDepth / 2 + 0.24);
    scene.add(mullion);

    final windowSeat = _box(
      width: 5.1,
      height: 0.34,
      depth: 1.1,
      color: const Color(0xFF5C4337),
      receiveShadow: true,
    )..position.setValues(1.0, 0.7, -roomDepth / 2 + 0.58);
    scene.add(windowSeat);

    final windowSeatBase = _box(
      width: 5.2,
      height: 0.78,
      depth: 1.04,
      color: const Color(0xFFB7A695),
      receiveShadow: true,
    )..position.setValues(1.0, 0.25, -roomDepth / 2 + 0.6);
    scene.add(windowSeatBase);

    _addRadiator(scene, roomDepth);
    _addDeskTapTarget(scene, roomDepth);

    final laptopBase = _box(
      width: 0.64,
      height: 0.05,
      depth: 0.42,
      color: const Color(0xFFB8AFA7),
    )..position.setValues(2.55, 0.9, -roomDepth / 2 + 0.38);
    scene.add(laptopBase);

    final laptopScreen =
        _box(
            width: 0.62,
            height: 0.4,
            depth: 0.04,
            color: const Color(0xFF272324),
          )
          ..position.setValues(2.55, 1.12, -roomDepth / 2 + 0.29)
          ..rotation.x = -0.35;
    scene.add(laptopScreen);

    final screenGlow = _box(
      width: 0.5,
      height: 0.28,
      depth: 0.01,
      color: const Color(0xFFB8705C),
    )..position.setValues(2.55, 1.12, -roomDepth / 2 + 0.26);
    scene.add(screenGlow);

    _addDeskAccessories(scene, roomDepth);

    final frame = _box(
      width: 0.55,
      height: 0.82,
      depth: 0.06,
      color: const Color(0xFFC3B9AE),
    )..position.setValues(0.7, 1.18, -roomDepth / 2 + 0.43);
    scene.add(frame);

    final candle =
        three.Mesh(
            three.CylinderGeometry(0.09, 0.09, 0.16, 14),
            three.MeshPhongMaterial.fromMap({
              'color': _hex(const Color(0xFFD5CCC0)),
            }),
          )
          ..position.setValues(1.45, 0.92, -roomDepth / 2 + 0.38)
          ..castShadow = true;
    scene.add(candle);

    final pendantStem = _box(
      width: 0.05,
      height: 0.82,
      depth: 0.05,
      color: const Color(0xFF1D1715),
    )..position.setValues(2.4, 4.15, -0.9);
    scene.add(pendantStem);

    final pendant =
        three.Mesh(
            three.SphereGeometry(0.3, 18, 18),
            three.MeshPhongMaterial.fromMap({
              'color': _hex(const Color(0xFFE0BDAD)),
              'emissive': 0xf0b89e,
              'emissiveIntensity': 0.18,
            }),
          )
          ..position.setValues(2.4, 3.55, -0.9)
          ..castShadow = true;
    scene.add(pendant);

    // Drop the imported Mallory sectional into the room as a test. The model
    // loads asynchronously, so we let it stream in without blocking the rest of
    // the scene from appearing. Every knob for it lives in the method below.
    unawaited(_addMallorySectionalTest(scene));
  }

  // ===========================================================================
  // Mallory Tufted Upholstered Sectional — imported glTF/GLB test placement.
  //
  // >>> THIS IS THE PLACE TO TWEAK THE SECTIONAL BY HAND <<<
  // Change a constant below and hot-restart (not just hot-reload) to see it:
  //
  //   _malloryAsset        Which file gets loaded. Export the model to a .glb
  //                        (Blender: File → Export → glTF Binary) so its textures
  //                        are embedded, drop it in assets/, and point this at it.
  //                        The `assets/` line in pubspec.yaml already bundles it.
  //   _malloryAutoFit      When true, the model is auto-scaled to
  //                        _malloryFitCells cells wide so it shows up at a sane
  //                        size whatever units it was authored in. Set it to false
  //                        to scale by hand with _malloryRawScale instead.
  //   _malloryFitCells     Target width in grid cells, used when _malloryAutoFit
  //                        is true.
  //   _malloryRawScale     Manual uniform scale, used when _malloryAutoFit is
  //                        false.
  //   _malloryX/_malloryZ  Where it sits on the floor, in world units. The floor
  //                        spans roughly -5..5 in X and -4..4 in Z; (0, 0) is the
  //                        centre. Larger Z is toward the camera.
  //   _malloryLift         World Y the model's base rests at. The visible plank
  //                        surface is ~0.04, so that is the default; raise (+) to
  //                        float it, lower toward 0 to sink it into the floor.
  //   _malloryQuarterTurns Spin around the vertical axis in 90° steps (0-3),
  //                        same convention as the rest of the room furniture.
  // ===========================================================================
  static const String _malloryAsset = 'assets/upholstered_sectional.glb';
  static const bool _malloryAutoFit = true;
  static const double _malloryFitCells = 3.0;
  static const double _malloryRawScale = 0.01;
  static const double _malloryX = -1.6;
  static const double _malloryZ = 1.6;
  static const double _malloryLift = 0.04;
  static const int _malloryQuarterTurns = 0;

  Future<void> _addMallorySectionalTest(three.Scene scene) async {
    three.Object3D? model;
    try {
      // glTF/GLB is self-contained: textures are embedded, so there is nothing
      // external to resolve. GLTFLoader returns the parsed scene graph.
      final gltf = await three.GLTFLoader().fromAsset(_malloryAsset);
      model = gltf?.scene;
    } catch (error, stackTrace) {
      debugPrint('Mallory sectional failed to load: $error\n$stackTrace');
      return;
    }

    if (model == null || !mounted || _threeJs == null) {
      return;
    }
    final sectional = model;

    // Scale first, measuring the model in its unrotated frame so auto-fit always
    // matches its true width; then apply the rotation. By default we fit the
    // model to a target width so it is visible whatever units it was authored in,
    // otherwise we fall back to the manual scale.
    var scale = _malloryRawScale;
    if (_malloryAutoFit) {
      final nativeSize = three.BoundingBox()
          .setFromObject(sectional)
          .getSize(three.Vector3.zero());
      if (nativeSize.x > 0) {
        scale = _malloryFitCells * RoomEditorController.cellSize / nativeSize.x;
      }
    }
    sectional.scale.setValues(scale, scale, scale);
    sectional.rotation.y = _malloryQuarterTurns * math.pi / 2;

    // Re-measure after scaling/rotating, then rest it on the floor at the target
    // spot. Import pivots are unpredictable, so we recentre from the bounding box
    // rather than trusting the model's own origin. If it parsed but carried no
    // geometry the bounds come back empty (min.y == +infinity); fall back to a
    // plain placement so the model stays in view instead of flying to infinity.
    final bounds = three.BoundingBox().setFromObject(sectional);
    if (bounds.isEmpty()) {
      debugPrint('Mallory sectional loaded but has no geometry to place.');
      sectional.position.setValues(_malloryX, _malloryLift, _malloryZ);
    } else {
      final center = bounds.getCenter(three.Vector3.zero());
      sectional.position.setValues(
        _malloryX - center.x,
        _malloryLift - bounds.min.y,
        _malloryZ - center.z,
      );
    }

    sectional.traverse((object) {
      object.castShadow = true;
      object.receiveShadow = true;
    });

    if (!mounted || _threeJs == null) {
      return;
    }
    scene.add(sectional);
  }

  void _addSlopedCeilingDetails(three.Scene scene, double roomDepth) {
    final rearZ = -roomDepth / 2 + 0.24;

    final leftSkylight =
        three.Mesh(
            three.BoxGeometry(1.42, 0.46, 0.04),
            three.MeshPhongMaterial.fromMap({
              'color': _hex(const Color(0xFF151718)),
              'transparent': true,
              'opacity': 0.86,
            }),
          )
          ..position.setValues(-4.22, 4.44, rearZ + 0.03)
          ..rotation.z = -0.88
          ..receiveShadow = true;
    scene.add(leftSkylight);

    final topRail = _box(
      width: 4.6,
      height: 0.08,
      depth: 0.08,
      color: const Color(0xFF2C2927),
    )..position.setValues(1.65, 4.36, rearZ + 0.06);
    scene.add(topRail);
  }

  void _addRadiator(three.Scene scene, double roomDepth) {
    final rearZ = -roomDepth / 2 + 0.78;
    final body = _box(
      width: 4.7,
      height: 0.46,
      depth: 0.12,
      color: const Color(0xFFC8C0B6),
      y: 0.28,
      z: rearZ,
      receiveShadow: true,
    )..position.x = 0.92;
    scene.add(body);

    for (var index = 0; index < 13; index += 1) {
      final x = -1.26 + index * 0.18;
      final fin = _box(
        width: 0.035,
        height: 0.4,
        depth: 0.04,
        color: const Color(0xFFABA39B),
      )..position.setValues(x + 1.0, 0.29, rearZ + 0.08);
      scene.add(fin);
    }
  }

  void _addDeskTapTarget(three.Scene scene, double roomDepth) {
    _addRoomTapTarget(
      scene,
      target: _RoomTapTarget.desk,
      width: 5.8,
      height: 1.6,
      depth: 1.2,
      x: 1.0,
      y: 1.25,
      z: -roomDepth / 2 + 0.48,
    );
  }

  void _addDeskAccessories(three.Scene scene, double roomDepth) {
    final deskZ = -roomDepth / 2 + 0.36;

    for (var index = 0; index < 5; index += 1) {
      final book =
          _box(
              width: 0.09,
              height: 0.54 + index * 0.02,
              depth: 0.34,
              color: index.isEven
                  ? const Color(0xFFCDBFAF)
                  : const Color(0xFFAEB8B6),
            )
            ..position.setValues(-1.2 + index * 0.11, 1.03, deskZ + 0.02)
            ..rotation.z = -0.08 + index * 0.025;
      scene.add(book);
    }

    final penCup =
        three.Mesh(
            three.CylinderGeometry(0.13, 0.15, 0.34, 14),
            three.MeshPhongMaterial.fromMap({
              'color': _hex(const Color(0xFFC0B9AF)),
            }),
          )
          ..position.setValues(0.95, 1.08, deskZ)
          ..castShadow = true;
    scene.add(penCup);

    for (final pen in const [
      (x: 0.9, color: Color(0xFFB8775D), angle: -0.22),
      (x: 1.0, color: Color(0xFF43524B), angle: 0.18),
    ]) {
      final mesh =
          _box(width: 0.035, height: 0.5, depth: 0.035, color: pen.color)
            ..position.setValues(pen.x, 1.38, deskZ)
            ..rotation.z = pen.angle;
      scene.add(mesh);
    }

    final radioBody = _box(
      width: 0.68,
      height: 0.34,
      depth: 0.24,
      color: const Color(0xFF8FA092),
      x: 1.52,
      y: 1.06,
      z: deskZ,
    );
    scene.add(radioBody);

    final radioDial =
        three.Mesh(
            three.CylinderGeometry(0.085, 0.085, 0.035, 18),
            three.MeshPhongMaterial.fromMap({
              'color': _hex(const Color(0xFF53645C)),
            }),
          )
          ..position.setValues(1.28, 1.06, deskZ + 0.14)
          ..rotation.x = math.pi / 2
          ..castShadow = true;
    scene.add(radioDial);

    for (var index = 0; index < 3; index += 1) {
      final grille = _box(
        width: 0.24,
        height: 0.02,
        depth: 0.018,
        color: const Color(0xFFC9C0B4),
        x: 1.66,
        y: 1.13 - index * 0.08,
        z: deskZ + 0.14,
      );
      scene.add(grille);
    }

    final tray =
        _box(
            width: 0.76,
            height: 0.06,
            depth: 0.32,
            color: const Color(0xFFC9B8A4),
          )
          ..position.setValues(2.06, 0.96, deskZ + 0.02)
          ..rotation.y = -0.08;
    scene.add(tray);

    final roundDish =
        three.Mesh(
            three.CylinderGeometry(0.14, 0.14, 0.04, 22),
            three.MeshPhongMaterial.fromMap({
              'color': _hex(const Color(0xFFD1C8BB)),
            }),
          )
          ..position.setValues(2.24, 1.03, deskZ + 0.05)
          ..castShadow = true;
    scene.add(roundDish);

    final stool =
        three.Mesh(
            three.CylinderGeometry(0.34, 0.38, 0.32, 22),
            three.MeshPhongMaterial.fromMap({
              'color': _hex(const Color(0xFF6F7E69)),
            }),
          )
          ..position.setValues(0.65, 0.66, -roomDepth / 2 + 1.35)
          ..castShadow = true;
    scene.add(stool);

    for (final x in const [0.43, 0.87]) {
      final leg = _box(
        width: 0.06,
        height: 0.34,
        depth: 0.06,
        color: const Color(0xFF3A2A24),
        x: x,
        y: 0.34,
        z: -roomDepth / 2 + 1.35,
      );
      scene.add(leg);
    }
  }

  void _addRoomTapTarget(
    three.Scene scene, {
    required _RoomTapTarget target,
    required double width,
    required double height,
    required double depth,
    required double x,
    required double y,
    required double z,
  }) {
    final material = three.MeshBasicMaterial.fromMap({
      'color': 0xffffff,
      'transparent': true,
      'opacity': 0.0,
      'depthWrite': false,
    });
    final mesh = three.Mesh(three.BoxGeometry(width, height, depth), material)
      ..position.setValues(x, y, z)
      ..userData['roomTapTarget'] = target
      ..renderOrder = 20;
    _roomTapTargets.add(mesh);
    scene.add(mesh);
  }

  void _attachPointerEvents() {
    if (_pointerEventsAttached) {
      return;
    }

    final threeJs = _threeJs;
    if (threeJs == null) {
      return;
    }

    final dom = threeJs.globalKey.currentState;
    if (dom == null) {
      return;
    }

    dom.addEventListener(three.PeripheralType.pointerdown, _onPointerDown);
    dom.addEventListener(three.PeripheralType.pointermove, _onPointerMove);
    dom.addEventListener(three.PeripheralType.pointerup, _onPointerUp);
    dom.addEventListener(three.PeripheralType.pointercancel, _onPointerUp);
    dom.addEventListener(three.PeripheralType.pointerleave, _onPointerUp);
    dom.addEventListener(three.PeripheralType.wheel, _onZoom);
    _pointerEventsAttached = true;
  }

  void _detachPointerEvents() {
    if (!_pointerEventsAttached) {
      return;
    }

    final threeJs = _threeJs;
    if (threeJs == null) {
      _pointerEventsAttached = false;
      return;
    }

    final dom = threeJs.globalKey.currentState;
    if (dom == null) {
      _pointerEventsAttached = false;
      return;
    }

    dom.removeEventListener(three.PeripheralType.pointerdown, _onPointerDown);
    dom.removeEventListener(three.PeripheralType.pointermove, _onPointerMove);
    dom.removeEventListener(three.PeripheralType.pointerup, _onPointerUp);
    dom.removeEventListener(three.PeripheralType.pointercancel, _onPointerUp);
    dom.removeEventListener(three.PeripheralType.pointerleave, _onPointerUp);
    dom.removeEventListener(three.PeripheralType.wheel, _onZoom);
    _pointerEventsAttached = false;
  }

  void _onPointerDown(dynamic event) {
    _activePointers.add((event.pointerId as num).toInt());
    if (_isPinching) {
      // A second finger landed: this is a pinch, not a drag/tilt.
      _cancelInteraction();
      return;
    }
    _recordPointerPosition(event, isDown: true);
    _pendingTapTarget = null;
    _cameraTiltCandidate = false;
    _cameraTiltActive = false;
    _updatePointer(event);
    _raycaster.setFromCamera(_pointer, _camera);
    final intersections = _raycaster.intersectObjects(
      _sceneFurniture.values.map((item) => item.root).toList(),
      true,
    );

    if (intersections.isEmpty) {
      final roomIntersections = _raycaster.intersectObjects(
        _roomTapTargets,
        true,
      );
      if (roomIntersections.isNotEmpty) {
        _pendingTapTarget = _resolveRoomTapTarget(
          roomIntersections.first.object,
        );
        widget.controller.selectItem(null);
        _beginCameraTiltCandidate(event);
        return;
      }

      widget.controller.selectItem(null);
      _beginCameraTiltCandidate(event);
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
    final placed = widget.controller.placedItemById(sceneFurniture.itemId);
    if (placed != null) {
      _pendingTapTarget = _tapTargetForDefinition(
        widget.controller.definitionFor(placed.definitionId),
      );
    }

    if (_raycaster.ray.intersectPlane(_dragPlane, _dragIntersection) != null) {
      _dragOffset
        ..setFrom(_dragIntersection)
        ..sub(sceneFurniture.root.position);
    }

    _syncSceneWithController();
  }

  void _onPointerMove(dynamic event) {
    if (_isPinching) {
      // Pinch zoom is handled by _onZoom; ignore drag/tilt while two fingers
      // are down.
      return;
    }
    _recordPointerPosition(event, isDown: false);
    if (_pointerTravel > 10) {
      _pendingTapTarget = null;
    }

    if (_activeDragItemId == null) {
      _updateCameraTilt(event);
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

  void _onPointerUp([dynamic event]) {
    if (event != null) {
      _activePointers.remove((event.pointerId as num).toInt());
      _recordPointerPosition(event, isDown: false);
    }

    final tapTarget = _pointerTravel <= 10 ? _pendingTapTarget : null;

    if (_activeDragItemId == null) {
      final wasTilting = _cameraTiltActive;
      _cameraTiltCandidate = false;
      _cameraTiltActive = false;
      _pendingTapTarget = null;
      if (wasTilting) {
        return;
      }
      _handleRoomTapTarget(tapTarget);
      return;
    }

    if (_dragPreviewOrigin != null && _dragPreviewValid) {
      widget.controller.movePlacedItem(_activeDragItemId!, _dragPreviewOrigin!);
    }

    _activeDragItemId = null;
    _dragPreviewOrigin = null;
    _dragPreviewValid = true;
    _pendingTapTarget = null;
    _cameraTiltCandidate = false;
    _cameraTiltActive = false;
    _syncSceneWithController();
    _handleRoomTapTarget(tapTarget);
  }

  void _beginCameraTiltCandidate(dynamic event) {
    _cameraTiltCandidate = true;
    _cameraTiltActive = false;
    _yawAtDragStart = _cameraYaw;
    _cameraTiltPointerStartX = _eventClientX(event);
  }

  void _updateCameraTilt(dynamic event) {
    if (!_cameraTiltCandidate || widget.deskFocused || widget.nightMode) {
      return;
    }

    final deltaX = _eventClientX(event) - _cameraTiltPointerStartX;
    if (!_cameraTiltActive && deltaX.abs() < _cameraTiltStartThreshold) {
      return;
    }

    _cameraTiltActive = true;
    _pendingTapTarget = null;
    // Full 360° turn — no clamp; wrap into [0, 2π) so the value stays bounded.
    final twoPi = 2 * math.pi;
    _cameraYaw = (_yawAtDragStart - deltaX * _yawSensitivity) % twoPi;
    _refreshCamera();
  }

  void _refreshCamera() {
    final threeJs = _threeJs;
    if (threeJs == null) {
      return;
    }

    final width = threeJs.width <= 0 ? 1.0 : threeJs.width;
    final height = threeJs.height <= 0 ? 1.0 : threeJs.height;
    _configureCamera(Size(width, height));
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
          _threeJs!.scene.remove(removed.root);
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
    _threeJs!.scene.add(root);

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

  _RoomTapTarget? _resolveRoomTapTarget(three.Object3D? object) {
    var current = object;
    while (current != null) {
      final value = current.userData['roomTapTarget'];
      if (value is _RoomTapTarget) {
        return value;
      }
      current = current.parent;
    }
    return null;
  }

  _RoomTapTarget? _tapTargetForDefinition(RoomItemDefinition definition) {
    return switch (definition.visualKind) {
      RoomItemVisualKind.bed => _RoomTapTarget.bed,
      RoomItemVisualKind.vanity => _RoomTapTarget.desk,
      _ => null,
    };
  }

  void _handleRoomTapTarget(_RoomTapTarget? target) {
    switch (target) {
      case _RoomTapTarget.desk:
        widget.onTapDesk?.call();
        return;
      case _RoomTapTarget.bed:
        widget.onTapBed?.call();
        return;
      case null:
        return;
    }
  }

  void _recordPointerPosition(dynamic event, {required bool isDown}) {
    final x = _eventClientX(event);
    final y = _eventClientY(event);
    if (isDown) {
      _pointerDownX = x;
      _pointerDownY = y;
    }
    _pointerLastX = x;
    _pointerLastY = y;
  }

  double get _pointerTravel {
    final dx = _pointerLastX - _pointerDownX;
    final dy = _pointerLastY - _pointerDownY;
    return math.sqrt(dx * dx + dy * dy);
  }

  void _updatePointer(dynamic event) {
    final threeJs = _threeJs;
    if (threeJs == null) {
      return;
    }

    final box =
        threeJs.globalKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }

    final width = box.size.width;
    final height = box.size.height;
    if (width <= 0 || height <= 0) {
      return;
    }

    final localPosition = box.globalToLocal(
      Offset(_eventClientX(event), _eventClientY(event)),
    );
    _pointer.x = localPosition.dx / width * 2 - 1;
    _pointer.y = -(localPosition.dy / height) * 2 + 1;
  }

  double _eventClientX(dynamic event) => (event.clientX as num).toDouble();

  double _eventClientY(dynamic event) => (event.clientY as num).toDouble();

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
        color: const Color(0xFFD1C8BD),
        y: 0.22,
      ),
    );
    group.add(
      _box(
        width: 2.76,
        height: 1.02,
        depth: 0.18,
        color: const Color(0xFFC6C1B8),
        y: 0.72,
        z: -1.68,
      ),
    );
    group.add(
      _box(
        width: 2.56,
        height: 0.18,
        depth: 3.0,
        color: const Color(0xFFBFB8AF),
        y: 0.54,
      ),
    );
    group.add(
      _box(
        width: 2.54,
        height: 0.2,
        depth: 3.0,
        color: const Color(0xFFCFC7BD),
        y: 0.78,
      ),
    );
    group.add(
      _box(
        width: 2.34,
        height: 0.16,
        depth: 2.82,
        color: const Color(0xFFD9D2C7),
        y: 0.91,
      ),
    );
    group.add(
      _box(
        width: 0.86,
        height: 0.18,
        depth: 0.58,
        color: const Color(0xFFE2DBD0),
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
        color: const Color(0xFFE2DBD0),
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
        color: const Color(0xFFC8B8A5),
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
        color: const Color(0xFFBCA992),
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
            color: const Color(0xFFC7B7A6),
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
        color: const Color(0xFFB5BDC5),
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
        color: const Color(0xFFC59F92),
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
        color: const Color(0xFFD7B693),
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
    bool receiveShadow = true,
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

  Future<void> _yieldSceneStep() => Future<void>.delayed(Duration.zero);

  void _syncSceneVisibility() {
    final threeJs = _threeJs;
    if (threeJs == null) {
      return;
    }

    threeJs.visible = widget.isActive;
  }
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

class _RoomScenePlaceholder extends StatelessWidget {
  const _RoomScenePlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1513), Color(0xFF110E0C)],
        ),
      ),
      child: Center(
        child: Container(
          width: 220,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: const Color(0xFF201916).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Color(0xFFF0C6A9),
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Preparing your room',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'The scene loads in the background so the rest of the app stays responsive.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFD8C3B5),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
