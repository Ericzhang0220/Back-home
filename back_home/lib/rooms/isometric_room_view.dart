import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

import 'furniture_models.dart';
import 'room_state.dart';

enum _RoomTapTarget { desk, bed, radio, window }

typedef _CameraViewState = ({
  three.Vector3 panOffset,
  double yaw,
  double pitch,
  double zoom,
});

/// Converts the room camera's portrait-friendly vertical FOV for a viewport,
/// capping the resulting horizontal FOV so wide screens do not become a
/// distorted ultra-wide lens.
double roomVerticalFovForAspect(
  double baseVerticalFov,
  double aspect, {
  double maxHorizontalFov = 82,
}) {
  final safeAspect = aspect.clamp(0.1, 10.0).toDouble();
  final verticalRadians = baseVerticalFov * math.pi / 180;
  final horizontalRadians =
      2 * math.atan(math.tan(verticalRadians / 2) * safeAspect);
  final maxHorizontalRadians = maxHorizontalFov * math.pi / 180;
  if (horizontalRadians <= maxHorizontalRadians) {
    return baseVerticalFov;
  }
  return 2 *
      math.atan(math.tan(maxHorizontalRadians / 2) / safeAspect) *
      180 /
      math.pi;
}

/// Converts a local clock value into the room sky's normalized 24-hour time.
/// Seconds and milliseconds are retained so celestial motion stays continuous.
double skyTimeOfDayForDateTime(DateTime dateTime) {
  final seconds =
      dateTime.hour * 3600 +
      dateTime.minute * 60 +
      dateTime.second +
      dateTime.millisecond / 1000;
  return seconds / Duration.secondsPerDay;
}

/// Position along the east-to-west celestial arc. Sunrise is at `0.25`, noon
/// at `0.5`, sunset at `0.75`; the moon follows the same arc twelve hours later.
({double horizontal, double altitude}) skyCelestialArc(
  double timeOfDay, {
  bool moon = false,
}) {
  final normalized = (timeOfDay % 1.0 + 1.0) % 1.0;
  final angle = (normalized - 0.25) * 2 * math.pi + (moon ? math.pi : 0);
  return (horizontal: math.cos(angle), altitude: math.sin(angle));
}

/// Keeps an outdoor camera facing away from the room while allowing a broad
/// view of the landscape. Angles beyond the outward hemisphere are clamped.
double clampOutwardCameraYaw(double yaw, {double limit = 35 * math.pi / 180}) {
  final twoPi = 2 * math.pi;
  final signed = ((yaw + math.pi) % twoPi + twoPi) % twoPi - math.pi;
  return signed.clamp(-limit, limit).toDouble();
}

class IsometricRoomView extends StatefulWidget {
  const IsometricRoomView({
    super.key,
    required this.controller,
    required this.isActive,
    this.deskFocused = false,
    this.nightMode = false,
    this.outsideView = false,
    this.onTapDesk,
    this.onTapBed,
    this.onTapRadio,
    this.onTapWindow,
    this.onDoubleTapRoom,
    this.skyWeather = SkyWeather.clear,
    this.skyTimeOfDay,
    this.cameraZoom = 1,
    this.cameraRotateSensitivity = 1,
    this.showFurnitureColliders = false,
    this.canMoveFurniture = false,
    this.onSelectedScreenPositionChanged,
    this.rotateSelectedWithDrag = false,
    this.onRotateSelectedBy,
  });

  /// Allows widget tests to exercise the room UI without opening a GL context.
  static bool rendererEnabled = true;

  final RoomEditorController controller;
  final bool isActive;
  final bool deskFocused;
  final bool nightMode;
  final bool outsideView;
  final VoidCallback? onTapDesk;
  final VoidCallback? onTapBed;

  /// Fired when the radio on the desk is tapped — used to open the music picker.
  final VoidCallback? onTapRadio;
  final VoidCallback? onTapWindow;
  final VoidCallback? onDoubleTapRoom;

  /// Weather shown through the window.
  final SkyWeather skyWeather;

  /// Time of day for the sky as a fraction of the day in `[0, 1)` (0 = midnight,
  /// 0.25 = sunrise, 0.5 = noon, 0.75 = sunset). When null the real clock is used.
  final double? skyTimeOfDay;
  final double cameraZoom;
  final double cameraRotateSensitivity;
  final bool showFurnitureColliders;

  /// Enables the room editor's drag-to-move furniture interactions.
  final bool canMoveFurniture;

  /// Reports the selected furniture's screen position within this view.
  final ValueChanged<Offset?>? onSelectedScreenPositionChanged;

  /// When true, dragging the selected furniture rotates it instead of moving it.
  final bool rotateSelectedWithDrag;
  final ValueChanged<double>? onRotateSelectedBy;

  @override
  State<IsometricRoomView> createState() => _IsometricRoomViewState();
}

class _IsometricRoomViewState extends State<IsometricRoomView> {
  static const Duration _sceneWarmupDelay = Duration(milliseconds: 350);

  // --- Centered 360° free-look camera (main view) -------------------------
  // The main view stands in the middle of the room and turns a full 360°.
  // >>> Tweak these to change the feel of the centered camera <<<
  static const double _cameraTiltStartThreshold =
      10; // px dead-zone before a drag becomes a turn
  static const double _yawSensitivity =
      0.008; // radians turned per pixel dragged
  static const double _pitchSensitivity =
      0.006; // vertical aim units per pixel dragged
  static const double _eyeHeight = 1.9; // camera height at the room centre
  static const double _lookPitch =
      -0.22; // vertical aim (negative = look slightly down)
  static const double _minLookPitch = -1.2;
  static const double _maxLookPitch = 0.75;
  static const double _mainFov = 64; // field of view for the centred view
  static const double _focusFov =
      42; // field of view in the desk/night focus views
  static const double _minFov =
      26; // pinch-zoom field-of-view clamp (zoomed in)
  static const double _maxFov =
      84; // pinch-zoom field-of-view clamp (zoomed out)
  static const double _wallCornerSealSize = 0.08;
  static const double _wallCornerSealInset = 0.22;

  three.ThreeJS? _threeJs;
  late final three.PerspectiveCamera _camera;

  final Map<String, _SceneFurniture> _sceneFurniture = {};
  final Map<String, three.Mesh> _furnitureColliderMeshes = {};
  three.Mesh? _cameraColliderMesh;
  three.Line? _debugCenterRay;
  final three.Raycaster _raycaster = three.Raycaster();
  final three.Vector2 _pointer = three.Vector2.zero();
  final three.Plane _dragPlane = three.Plane();
  final three.Vector3 _dragIntersection = three.Vector3.zero();
  final three.Vector3 _dragOffset = three.Vector3.zero();
  final List<three.Object3D> _roomTapTargets = [];
  three.Group? _skyGroup;
  three.Group? _skySun;
  three.Group? _skyMoon;
  _SkyLook? _activeSkyLook;
  final List<three.Group> _skyCloudGroups = [];
  final List<three.Mesh> _skyRainDrops = [];
  double _liveSkyUpdateElapsed = 0;
  Timer? _skyClockTimer; // refreshes the sky in "Live" (real-clock) time mode

  Timer? _sceneStartTimer;
  Timer? _pendingRoomTapTimer;
  bool _sceneReady = false;
  bool _sceneRequested = false;
  bool _threeConfigured = false;
  bool _pointerEventsAttached = false;
  String? _activeDragItemId;
  GridPoint? _dragPreviewOrigin;
  bool _dragPreviewValid = true;
  _RoomTapTarget? _pendingTapTarget;
  // The pending point comes from the touch ray; the focus anchor is normalized
  // to the relevant furniture centre before opening the activity view.
  three.Vector3? _pendingTapAnchor;
  three.Vector3? _focusAnchor;
  String? _pendingFurnitureTapItemId;
  double _pointerDownX = 0;
  double _pointerDownY = 0;
  double _pointerLastX = 0;
  double _pointerLastY = 0;
  bool _cameraTiltCandidate = false;
  bool _cameraTiltActive = false;
  Offset? _lastSelectedScreenPosition;
  String? _activeRotationItemId;
  double _rotationDragLastX = 0;
  double _cameraYaw =
      0; // horizontal look angle (radians); 0 = facing the far wall
  double _cameraPitch = _lookPitch;
  double _currentCameraYaw = 0;
  double _currentCameraPitch = _lookPitch;
  _CameraViewState? _preNightCameraState;
  _CameraViewState? _preDeskCameraState;
  _CameraViewState? _preOutsideCameraState;
  double _yawAtDragStart = 0;
  double _pitchAtDragStart = _lookPitch;
  double _cameraTiltPointerStartX = 0;
  double _cameraTiltPointerStartY = 0;
  // Seated desk view: the camera stays put but can pan its gaze within the
  // front hemisphere. Base = the look toward the desk; offsets are the drag.
  double _deskBaseYaw = 0;
  double _deskBasePitch = 0;
  double _deskYaw = 0;
  double _deskPitch = 0;
  double _deskYawAtDragStart = 0;
  double _deskPitchAtDragStart = 0;
  static const double _deskYawLimit = math.pi / 2; // front hemisphere only
  static const double _deskPitchMin = -0.5;
  static const double _deskPitchMax = 0.5;
  static const double _outsidePitchMin = -0.85;
  static const double _outsidePitchMax = 0.72;

  // Smooth camera motion + pinch zoom. The camera eases toward these targets
  // every frame instead of snapping; _zoom drives the field of view.
  final three.Vector3 _cameraTargetPos = three.Vector3.zero();
  final three.Vector3 _cameraTargetLook = three.Vector3.zero();
  final three.Vector3 _cameraCurrentLook = three.Vector3.zero();
  bool _cameraPosed = false;
  Size? _layoutViewportSize;
  bool _viewportSyncScheduled = false;
  double _viewportAspect = 1;
  double _zoom = 1.0;
  double _currentZoom = 1.0;
  double _cameraTargetBaseFov = _mainFov;
  final Set<int> _activePointers = <int>{};
  final Map<int, Offset> _activePointerPositions = <int, Offset>{};
  bool _multiTouchSequenceActive = false;
  final three.Vector3 _cameraPanOffset = three.Vector3.zero();
  Offset? _lastPanCentroid;
  // Mesh-level world-space bounds for the imported sectional. Keeping these
  // separate preserves its open center and detached ottoman.
  final List<
    ({
      double centerX,
      double centerZ,
      double halfWidth,
      double halfDepth,
      double minY,
      double maxY,
    })
  >
  _sofaColliders = [];
  final List<three.Mesh> _sofaColliderMeshes = [];

  static const double _minZoom = 0.62;
  static const double _maxZoom = 2.4;
  static const double _zoomInStep = 1.06;
  static const double _zoomOutStep = 0.94;
  static const double _cameraPanUnitsPerPixel = 0.0075;
  static const double _cameraHeightPanUnitsPerPixel = 0.006;
  static const double _minCameraHeightOffset = -0.9;
  static const double _maxCameraHeightOffset = 2.8;
  static const double _cameraPanWallPaddingX = 0.4;
  static const double _cameraPanWallPaddingZ = 0.5;
  // How close the camera can get to furniture before it's blocked (world units).
  static const double _cameraColliderRadius = 0.1;
  // Furniture collider heights. These drive both camera collision and the
  // translucent debug overlays, so visualized clearance matches behavior.
  static const double _defaultFurnitureColliderHeight = 4.8;
  static const double _bedColliderHeight = 1.2;
  static const double _sofaColliderHeightLimit = 1.25;
  static const double _debugCenterRayLength = 20.0;
  // Higher = snappier camera transitions (eases ~this fraction per second).
  static const double _cameraLerpSpeed = 7.0;
  static const double _bedFocusCameraLerpSpeed = 2.0;
  // The good-night camera settles directly over the bed, high enough to clear
  // its headboard and pillows without feeling detached from it.
  static const double _bedOverheadCameraHeight = 2.1;
  // Stop slightly short of the bed's centre, on the side the camera entered
  // from, so a side approach does not appear to fly past the bed.
  static const double _bedApproachInset = 0.55;
  static const double _zoomLerpSpeed = 9.0;
  static const double _rotationLerpSpeed = 9.0;
  static const double _rotationDragDegreesPerPixel = 0.12;
  // Main-room taps wait this long before firing so a second tap can reveal
  // chrome instead of opening an interactable. Tune this for double-tap feel.
  static const Duration _roomTapDoubleTapDebounce = Duration(milliseconds: 300);

  bool get _isPinching => _activePointers.length >= 2;
  bool get _isCameraPanning => _activePointers.length >= 3;
  bool get _isCameraHeightPanning => _activePointers.length >= 4;
  int get _cameraPanPointerCount => _isCameraHeightPanning ? 4 : 3;
  bool get _delaysRoomTapActions =>
      !widget.canMoveFurniture && !widget.deskFocused && !widget.nightMode;

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
        widget.nightMode != oldWidget.nightMode ||
        widget.outsideView != oldWidget.outsideView;
    if (focusChanged && _threeConfigured && _threeJs != null) {
      _cancelPendingRoomTap();
      final enteringNight = widget.nightMode && !oldWidget.nightMode;
      final leavingNight = !widget.nightMode && oldWidget.nightMode;
      final enteringDesk = widget.deskFocused && !oldWidget.deskFocused;
      final leavingDesk = !widget.deskFocused && oldWidget.deskFocused;
      final enteringOutside = widget.outsideView && !oldWidget.outsideView;
      final leavingOutside = !widget.outsideView && oldWidget.outsideView;
      if (enteringOutside) {
        _preOutsideCameraState = _captureCameraViewState();
        _resetFocusedCameraState();
        _cameraYaw = 0;
        _cameraPitch = -0.04;
      } else if (leavingOutside && _preOutsideCameraState != null) {
        _restoreCameraViewState(_preOutsideCameraState!);
        _preOutsideCameraState = null;
      } else if (enteringNight) {
        _preNightCameraState = _captureCameraViewState();
        _resetFocusedCameraState();
      } else if (leavingNight && _preNightCameraState != null) {
        _restoreCameraViewState(_preNightCameraState!);
        _preNightCameraState = null;
      } else if (enteringDesk) {
        _preDeskCameraState = _captureCameraViewState();
        _resetFocusedCameraState();
      } else if (leavingDesk && _preDeskCameraState != null) {
        _restoreCameraViewState(_preDeskCameraState!);
        _preDeskCameraState = null;
      } else {
        _resetFocusedCameraState();
      }
      _lastPanCentroid = null;
      if (!widget.outsideView) {
        // Sit down facing the desk; the seated look starts centred each time.
        _deskYaw = 0;
        _deskPitch = 0;
      }
      _configureCamera(_currentViewportSize());
    }

    if (_threeConfigured &&
        _threeJs != null &&
        (widget.skyWeather != oldWidget.skyWeather ||
            widget.skyTimeOfDay != oldWidget.skyTimeOfDay)) {
      _rebuildSky();
    }
    if (_threeConfigured &&
        _threeJs != null &&
        widget.cameraZoom != oldWidget.cameraZoom) {
      _refreshCamera();
    }
    if (_sceneReady &&
        widget.showFurnitureColliders != oldWidget.showFurnitureColliders) {
      _syncColliderVisibility();
    }
    _syncSkyClock();

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

  _CameraViewState _captureCameraViewState() => (
    panOffset: three.Vector3(
      _camera.position.x,
      _camera.position.y - _eyeHeight,
      _camera.position.z,
    ),
    yaw: _currentCameraYaw,
    pitch: _currentCameraPitch,
    zoom: _currentZoom,
  );

  void _restoreCameraViewState(_CameraViewState state) {
    _cameraPanOffset.setFrom(state.panOffset);
    _cameraYaw = state.yaw;
    _cameraPitch = state.pitch;
    _zoom = state.zoom;
  }

  void _resetFocusedCameraState() {
    _zoom = 1.0;
    _currentZoom = 1.0;
    _cameraPanOffset.setValues(0, 0, 0);
  }

  @override
  void dispose() {
    _sceneStartTimer?.cancel();
    _skyClockTimer?.cancel();
    _pendingRoomTapTimer?.cancel();
    widget.controller.removeListener(_handleControllerChanged);
    if (_threeConfigured && _threeJs != null) {
      _detachPointerEvents();
      _threeJs!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _scheduleViewportSync(constraints.biggest);
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
      },
    );
  }

  void _scheduleViewportSync(Size size) {
    if (size.width <= 0 || size.height <= 0 || size == _layoutViewportSize) {
      return;
    }
    _layoutViewportSize = size;
    if (_viewportSyncScheduled) {
      return;
    }
    _viewportSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportSyncScheduled = false;
      if (!mounted || !_threeConfigured) {
        return;
      }
      _configureCamera(_currentViewportSize());
    });
  }

  Size _currentViewportSize() {
    final layoutSize = _layoutViewportSize;
    if (layoutSize != null && layoutSize.width > 0 && layoutSize.height > 0) {
      return layoutSize;
    }
    final threeJs = _threeJs;
    if (threeJs == null) {
      return const Size(1, 1);
    }
    return Size(
      threeJs.width <= 0 ? 1 : threeJs.width,
      threeJs.height <= 0 ? 1 : threeJs.height,
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

    _configureCamera(_currentViewportSize());
    _cameraColliderMesh = _createCameraColliderMesh()
      ..visible = widget.showFurnitureColliders;
    _updateCameraColliderMesh();
    threeJs.scene.add(_cameraColliderMesh!);
    _debugCenterRay = _createDebugCenterRay()
      ..visible = widget.showFurnitureColliders;
    threeJs.scene.add(_debugCenterRay!);
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
    _layoutViewportSize = size;
    _configureCamera(size);
  }

  void _configureCamera(Size size) {
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;

    _viewportAspect = safeWidth / safeHeight;
    _camera.aspect = _viewportAspect;
    _camera.near = 0.1;
    _camera.far = 80;

    final roomDepth =
        RoomEditorController.roomDepth * RoomEditorController.cellSize;
    final farWallZ = -roomDepth / 2;

    three.Vector3 basePos;
    three.Vector3 lookAt;
    final double baseFov;
    if (widget.outsideView) {
      // Pass through the centre of the opening and settle just beyond the
      // exterior wall. The gaze remains aimed into the landscape; outdoor drag
      // handling clamps yaw before it could turn back toward the room.
      basePos = three.Vector3(1.0, 2.32, farWallZ - 1.35);
      lookAt = three.Vector3(
        basePos.x + math.sin(_cameraYaw),
        basePos.y + _cameraPitch,
        basePos.z - math.cos(_cameraYaw),
      );
      baseFov = 54;
    } else if (widget.deskFocused) {
      // Fly to a close-up of the tapped desk, viewed from the room-centre side
      // so the camera stays inside the room wherever the desk sits.
      (basePos, lookAt) = _focusFraming(
        fallbackAnchor: three.Vector3(1.0, 0, farWallZ + 0.48),
        standDistance: 3.2,
        eyeHeight: 1.75,
        lookHeight: 1.15,
      );
      // Remember the seated forward look so drags can pan around it (front
      // hemisphere only). Yaw/pitch follow the same convention as free-look:
      // look dir = (sin yaw, pitch, -cos yaw).
      final dirX = lookAt.x - basePos.x;
      final dirZ = lookAt.z - basePos.z;
      final horizontal = math.sqrt(dirX * dirX + dirZ * dirZ);
      _deskBaseYaw = math.atan2(dirX, -dirZ);
      _deskBasePitch = horizontal < 1e-3
          ? 0
          : (lookAt.y - basePos.y) / horizontal;
      baseFov = _focusFov;
    } else if (widget.nightMode) {
      // The good-night overlay does not need a bed close-up, so fly straight
      // above the bed instead of orbiting toward it. Keeping the current look
      // direction avoids a disorienting turn when entering from elsewhere in
      // the room.
      final anchor = _focusAnchor ?? three.Vector3(-0.5, 0, -3.4);
      var approachX = _camera.position.x - anchor.x;
      var approachZ = _camera.position.z - anchor.z;
      final approachLength = math.sqrt(
        approachX * approachX + approachZ * approachZ,
      );
      if (approachLength < 1e-3) {
        // When already over the centre, keep a small offset behind the view
        // direction rather than arbitrarily choosing a side of the bed.
        approachX = -math.sin(_currentCameraYaw);
        approachZ = math.cos(_currentCameraYaw);
      } else {
        approachX /= approachLength;
        approachZ /= approachLength;
      }
      basePos = three.Vector3(
        anchor.x + approachX * _bedApproachInset,
        _bedOverheadCameraHeight,
        anchor.z + approachZ * _bedApproachInset,
      );
      lookAt = basePos.clone()
        ..add(
          three.Vector3(
            math.sin(_currentCameraYaw),
            _currentCameraPitch,
            -math.cos(_currentCameraYaw),
          ),
        );
      baseFov = _focusFov;
    } else {
      // Centred free-look: stand in the middle of the room and turn 360°.
      basePos = three.Vector3(0, _eyeHeight, 0);
      lookAt = three.Vector3(
        math.sin(_currentCameraYaw),
        _eyeHeight + _currentCameraPitch,
        -math.cos(_currentCameraYaw),
      );
      baseFov = _mainFov;
      basePos.add(_cameraPanOffset);
      lookAt.add(_cameraPanOffset);
    }

    _cameraTargetBaseFov = baseFov;
    _applyCameraFov();
    _cameraTargetPos.setFrom(basePos);
    _cameraTargetLook.setFrom(lookAt);

    // First configuration snaps into place; later changes ease in (see
    // _animateCamera), so switching views glides instead of teleporting.
    if (!_cameraPosed) {
      _camera.position.setFrom(_cameraTargetPos);
      _cameraCurrentLook.setFrom(_cameraTargetLook);
      _camera.lookAt(_cameraCurrentLook);
      _cameraPosed = true;
    }
  }

  /// Frames a focus view on [_focusAnchor] (the tapped furniture point, falling
  /// back to [fallbackAnchor]): the camera stands [standDistance] toward the
  /// room centre from the furniture at [eyeHeight], looking back at it. Standing
  /// on the centre side keeps the camera inside the room wherever the piece is.
  (three.Vector3, three.Vector3) _focusFraming({
    required three.Vector3 fallbackAnchor,
    required double standDistance,
    required double eyeHeight,
    required double lookHeight,
  }) {
    final anchor = _focusAnchor ?? fallbackAnchor;

    var dirX = -anchor.x;
    var dirZ = -anchor.z;
    final length = math.sqrt(dirX * dirX + dirZ * dirZ);
    if (length < 1e-3) {
      // Piece sits dead centre — back toward the near (+Z) side of the room.
      dirX = 0;
      dirZ = 1;
    } else {
      dirX /= length;
      dirZ /= length;
    }

    final halfWidth =
        RoomEditorController.roomWidth * RoomEditorController.cellSize / 2;
    final halfDepth =
        RoomEditorController.roomDepth * RoomEditorController.cellSize / 2;
    const wallPadding = 0.5;

    final basePos = three.Vector3(
      (anchor.x + dirX * standDistance)
          .clamp(-halfWidth + wallPadding, halfWidth - wallPadding)
          .toDouble(),
      eyeHeight,
      (anchor.z + dirZ * standDistance)
          .clamp(-halfDepth + wallPadding, halfDepth - wallPadding)
          .toDouble(),
    );
    final lookAt = three.Vector3(anchor.x, lookHeight, anchor.z);
    return (basePos, lookAt);
  }

  void _animateCamera(double dt) {
    _animateSky(dt);
    if (!_cameraPosed) {
      return;
    }
    _updateCameraColliderMesh();
    _updateDebugCenterRay();
    final nextZoom = _lerpDouble(
      _currentZoom,
      _zoom,
      1 - math.exp(-dt * _zoomLerpSpeed),
    );
    final zoomSettled = (nextZoom - _zoom).abs() < 0.0001;
    _currentZoom = zoomSettled ? _zoom : nextZoom;
    _applyCameraFov();

    final mainFreeLook = !widget.deskFocused && !widget.nightMode;
    final deskLook = widget.deskFocused && !widget.nightMode;
    // The night camera moves the eye but never changes the user's heading.
    // Main and desk views interpolate orientation as angles instead of blending
    // world-space look-at points. The latter can pass through the moving eye
    // during a transition and briefly invert the camera.
    var rotationSettled = true;
    if (mainFreeLook || deskLook) {
      final targetYaw = deskLook ? _deskBaseYaw + _deskYaw : _cameraYaw;
      final targetPitch = deskLook ? _deskBasePitch + _deskPitch : _cameraPitch;
      final rotationT = (1 - math.exp(-dt * _rotationLerpSpeed))
          .clamp(0.0, 1.0)
          .toDouble();
      final yawDelta = _shortestAngleDelta(_currentCameraYaw, targetYaw);
      final pitchDelta = targetPitch - _currentCameraPitch;
      rotationSettled = yawDelta.abs() < 0.0001 && pitchDelta.abs() < 0.0001;
      _currentCameraYaw = rotationSettled
          ? _normalizeRadians(targetYaw)
          : _normalizeRadians(_currentCameraYaw + yawDelta * rotationT);
      _currentCameraPitch = rotationSettled
          ? targetPitch
          : _lerpDouble(_currentCameraPitch, targetPitch, rotationT);
    }

    // Nothing to do once the camera has settled on its target.
    if (_camera.position.distanceToSquared(_cameraTargetPos) < 1e-8 &&
        rotationSettled &&
        zoomSettled) {
      return;
    }
    final cameraLerpSpeed = widget.nightMode
        ? _bedFocusCameraLerpSpeed
        : _cameraLerpSpeed;
    final t = (1 - math.exp(-dt * cameraLerpSpeed)).clamp(0.0, 1.0).toDouble();
    _camera.position.lerp(_cameraTargetPos, t);
    _updateCameraColliderMesh();
    _cameraCurrentLook.setValues(
      _camera.position.x + math.sin(_currentCameraYaw),
      _camera.position.y + _currentCameraPitch,
      _camera.position.z - math.cos(_currentCameraYaw),
    );
    _camera.lookAt(_cameraCurrentLook);
    _updateDebugCenterRay();
    _publishSelectedScreenPosition();
  }

  void _applyCameraFov() {
    // FOV easing is a direct exponential blend, not a spring, so it cannot
    // overshoot the target zoom.
    final effectiveZoom = (_currentZoom * widget.cameraZoom)
        .clamp(_minZoom, _maxZoom)
        .toDouble();
    final aspectAdjustedFov = roomVerticalFovForAspect(
      _cameraTargetBaseFov,
      _viewportAspect,
      maxHorizontalFov: widget.outsideView ? 60 : 82,
    );
    _camera.fov = (aspectAdjustedFov / effectiveZoom)
        .clamp(_minFov, _maxFov)
        .toDouble();
    _camera.updateProjectionMatrix();
  }

  double _lerpDouble(double from, double to, double t) =>
      from + (to - from) * t.clamp(0.0, 1.0);

  double _normalizeRadians(double angle) {
    final twoPi = 2 * math.pi;
    return (angle % twoPi + twoPi) % twoPi;
  }

  double _shortestAngleDelta(double from, double to) {
    final twoPi = 2 * math.pi;
    return ((to - from + math.pi) % twoPi + twoPi) % twoPi - math.pi;
  }

  void _onZoom(dynamic event) {
    if (_activePointers.length > 2) {
      return;
    }

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
    _pendingFurnitureTapItemId = null;
    _activeRotationItemId = null;
    _cameraTiltCandidate = false;
    _cameraTiltActive = false;
    _lastPanCentroid = _isCameraPanning
        ? _pointerCentroid(minPointers: _cameraPanPointerCount)
        : null;
    _syncSceneWithController();
  }

  void _scheduleSceneBootstrap() {
    if (!IsometricRoomView.rendererEnabled ||
        !widget.isActive ||
        _sceneRequested ||
        _sceneStartTimer != null) {
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
    // Anchored to the far half so it keeps lighting the desk niche.
    warmLamp.position.setValues(2.4, 3.7, -roomDepth / 2 + 3.2);
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

    // Back wall built around a window opening (x[-1.45, 3.45], y[1.0, 3.7]) so
    // the sky behind it is visible. Four segments frame the hole.
    final backWallZ = -roomDepth / 2 + 0.1;
    const backWallColor = Color(0xFFD4CCC2);
    for (final seg in const [
      (w: 3.55, h: 5.0, x: -3.225, y: 2.4), // left of window
      (w: 1.55, h: 5.0, x: 4.225, y: 2.4), // right of window
      (w: 4.9, h: 1.1, x: 1.0, y: 0.45), // below window
      (w: 4.9, h: 1.2, x: 1.0, y: 4.3), // above window
    ]) {
      scene.add(
        _box(
          width: seg.w,
          height: seg.h,
          depth: 0.22,
          color: backWallColor,
          receiveShadow: true,
        )..position.setValues(seg.x, seg.y, backWallZ),
      );
    }

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
    _addWallCornerSeals(scene, roomWidth, roomDepth);

    // castShadow:false so the ceiling does not block the key light's floor
    // shadows; its underside is still lit by ambient + the warm point lamp.
    final ceiling = _box(
      width: roomWidth,
      height: 0.2,
      depth: roomDepth,
      color: const Color(0xFFCBC0B5),
      castShadow: false,
      receiveShadow: false,
    )..position.setValues(0, 4.9, 0);
    scene.add(ceiling);

    _addSlopedCeilingDetails(scene, roomDepth);

    await _yieldSceneStep();
    if (!mounted) {
      return;
    }

    const frameColor = Color(0xFF4C392F);
    const frameWidth = 4.9;
    const frameHeight = 2.7;
    const frameThickness = 0.16;
    final frameZ = -roomDepth / 2 + 0.18;
    for (final bar in const [
      (w: frameWidth, h: frameThickness, x: 1.0, y: 1.08),
      (w: frameWidth, h: frameThickness, x: 1.0, y: 3.62),
      (w: frameThickness, h: frameHeight, x: -1.37, y: 2.35),
      (w: frameThickness, h: frameHeight, x: 3.37, y: 2.35),
    ]) {
      scene.add(
        _box(width: bar.w, height: bar.h, depth: 0.1, color: frameColor)
          ..position.setValues(bar.x, bar.y, frameZ),
      );
    }

    final rearWindowGlass = three.Mesh(
      three.BoxGeometry(4.45, 2.25, 0.04),
      three.MeshPhongMaterial.fromMap({
        'color': _hex(const Color(0xFFBFD8E8)),
        'transparent': true,
        'opacity': 0.12, // faint pane so the sky beyond shows through
        'depthWrite': false,
      }),
    )..position.setValues(1.0, 2.28, -roomDepth / 2 + 0.22);
    scene.add(rearWindowGlass);
    _addRoomTapTarget(
      scene,
      target: _RoomTapTarget.window,
      width: 4.45,
      height: 2.25,
      depth: 0.08,
      x: 1.0,
      y: 2.28,
      z: -roomDepth / 2 + 0.28,
    );

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

    final pendantZ = -roomDepth / 2 + 3.1;
    final pendantStem = _box(
      width: 0.05,
      height: 0.82,
      depth: 0.05,
      color: const Color(0xFF1D1715),
    )..position.setValues(2.4, 4.15, pendantZ);
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
          ..position.setValues(2.4, 3.55, pendantZ)
          ..castShadow = true;
    scene.add(pendant);

    _addDecorDoor(scene, roomWidth, roomDepth);
    _rebuildSky();
    _syncSkyClock();

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
      _buildSofaMeshColliders(sectional, scene);
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

  void _buildSofaMeshColliders(three.Object3D sectional, three.Scene scene) {
    _sofaColliders.clear();
    for (final mesh in _sofaColliderMeshes) {
      scene.remove(mesh);
    }
    _sofaColliderMeshes.clear();

    sectional.updateMatrixWorld(true);
    sectional.traverse((object) {
      if (object is! three.Mesh) {
        return;
      }
      final bounds = three.BoundingBox().setFromObject(object);
      if (bounds.isEmpty()) {
        return;
      }
      final size = bounds.getSize(three.Vector3.zero());
      if (size.x < 0.02 || size.y < 0.02 || size.z < 0.02) {
        return;
      }

      final minY = math.max(0.0, bounds.min.y);
      final maxY = math.min(_sofaColliderHeightLimit, bounds.max.y);
      if (maxY <= minY) {
        return;
      }
      final centerX = (bounds.min.x + bounds.max.x) / 2;
      final centerZ = (bounds.min.z + bounds.max.z) / 2;
      final halfWidth = size.x / 2;
      final halfDepth = size.z / 2;
      _sofaColliders.add((
        centerX: centerX,
        centerZ: centerZ,
        halfWidth: halfWidth,
        halfDepth: halfDepth,
        minY: minY,
        maxY: maxY,
      ));

      final colliderMesh = _createColliderMesh(opacity: 0.12)
        ..position.setValues(centerX, (minY + maxY) / 2, centerZ)
        ..scale.setValues(size.x, maxY - minY, size.z)
        ..visible = widget.showFurnitureColliders;
      _sofaColliderMeshes.add(colliderMesh);
      scene.add(colliderMesh);
    });
  }

  void _addSlopedCeilingDetails(three.Scene scene, double roomDepth) {
    final rearZ = -roomDepth / 2 + 0.24;

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

  // Decorative (non-functional) door on the right wall, in the near half.
  void _addDecorDoor(three.Scene scene, double roomWidth, double roomDepth) {
    final innerX = roomWidth / 2 - 0.21; // inner face of the right wall
    const doorZ = 2.6;
    const doorH = 2.1;
    final doorY = doorH / 2 - 0.05; // bottom resting just above the floor

    // Recessed casing.
    scene.add(
      _box(
        width: 0.06,
        height: doorH + 0.22,
        depth: 1.16,
        color: const Color(0xFF4A3326),
        receiveShadow: true,
      )..position.setValues(innerX - 0.02, doorY + 0.02, doorZ),
    );
    // Door slab.
    scene.add(
      _box(
        width: 0.09,
        height: doorH,
        depth: 0.96,
        color: const Color(0xFF6B4A38),
        receiveShadow: true,
      )..position.setValues(innerX - 0.08, doorY, doorZ),
    );
    // Two inset panels.
    for (final py in [doorY + 0.5, doorY - 0.5]) {
      scene.add(
        _box(
          width: 0.04,
          height: 0.66,
          depth: 0.62,
          color: const Color(0xFF583C2D),
        )..position.setValues(innerX - 0.13, py, doorZ),
      );
    }
    // Brass knob.
    scene.add(
      _box(width: 0.08, height: 0.1, depth: 0.1, color: const Color(0xFFC9A86B))
        ..position.setValues(innerX - 0.16, doorY, doorZ - 0.34),
    );
  }

  void _addWallCornerSeals(
    three.Scene scene,
    double roomWidth,
    double roomDepth,
  ) {
    final x = roomWidth / 2 - _wallCornerSealInset;
    final z = roomDepth / 2 - _wallCornerSealInset;
    for (final corner in [
      (x: -x, z: -z),
      (x: x, z: -z),
      (x: -x, z: z),
      (x: x, z: z),
    ]) {
      scene.add(
        _box(
          width: _wallCornerSealSize,
          height: 5.0,
          depth: _wallCornerSealSize,
          color: const Color(0xFF958B82),
          castShadow: false,
          receiveShadow: true,
        )..position.setValues(corner.x, 2.4, corner.z),
      );
    }
  }

  // === Landscape beyond the window ==========================================
  // The outdoor view is deliberately layered over a long stretch of Z depth:
  // sky and celestial bodies, distant clouds, hills, trees, then nearby rain.
  // This keeps the window from reading like a painted panel on the back wall.

  double _resolveTimeOfDay() {
    final t = widget.skyTimeOfDay;
    if (t != null) {
      return (t % 1.0 + 1.0) % 1.0;
    }
    return skyTimeOfDayForDateTime(DateTime.now());
  }

  void _rebuildSky() {
    final threeJs = _threeJs;
    if (threeJs == null) {
      return;
    }
    final previousCloudXs = [
      for (final cloud in _skyCloudGroups) cloud.position.x,
    ];
    final previousRainPositions = [
      for (final drop in _skyRainDrops)
        (x: drop.position.x, y: drop.position.y),
    ];
    final previous = _skyGroup;
    if (previous != null) {
      threeJs.scene.remove(previous);
      previous.dispose(); // free the old group's geometries/materials
    }
    _skySun = null;
    _skyMoon = null;
    _activeSkyLook = null;
    _skyCloudGroups.clear();
    _skyRainDrops.clear();
    final group = _buildSky(_resolveTimeOfDay(), widget.skyWeather);
    final reusableClouds = math.min(
      previousCloudXs.length,
      _skyCloudGroups.length,
    );
    for (var index = 0; index < reusableClouds; index += 1) {
      _skyCloudGroups[index].position.x = previousCloudXs[index];
    }
    final reusableRain = math.min(
      previousRainPositions.length,
      _skyRainDrops.length,
    );
    for (var index = 0; index < reusableRain; index += 1) {
      _skyRainDrops[index].position
        ..x = previousRainPositions[index].x
        ..y = previousRainPositions[index].y;
    }
    _skyGroup = group;
    threeJs.scene.add(group);
  }

  // Auto mode rebuilds atmospheric colours periodically while the animation
  // callback moves the sun and moon smoothly from the live device clock.
  void _syncSkyClock() {
    final live = widget.skyTimeOfDay == null;
    if (live && widget.isActive && _threeConfigured) {
      _skyClockTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && _threeJs != null && widget.skyTimeOfDay == null) {
          _rebuildSky();
        }
      });
    } else {
      _skyClockTimer?.cancel();
      _skyClockTimer = null;
    }
  }

  void _animateSky(double dt) {
    if (_skyGroup == null || !widget.isActive) {
      return;
    }

    for (var index = 0; index < _skyCloudGroups.length; index += 1) {
      final cloud = _skyCloudGroups[index];
      cloud.position.x += dt * (0.025 + (index % 3) * 0.012);
      if (cloud.position.x > 78) {
        cloud.position.x = -68;
      }
    }

    for (var index = 0; index < _skyRainDrops.length; index += 1) {
      final drop = _skyRainDrops[index];
      final speed = 2.8 + (index % 5) * 0.32;
      drop.position.y -= dt * speed;
      drop.position.x -= dt * speed * 0.08;
      if (drop.position.y < -1.2) {
        drop.position.y += 9.2;
        drop.position.x += 0.72;
      }
    }

    if (widget.skyTimeOfDay != null) {
      return;
    }
    _liveSkyUpdateElapsed += dt;
    if (_liveSkyUpdateElapsed < 0.2) {
      return;
    }
    _liveSkyUpdateElapsed = 0;
    _positionCelestialBodies(_resolveTimeOfDay());
  }

  three.Group _buildSky(double time, SkyWeather weather) {
    final group = three.Group();
    final roomDepth =
        RoomEditorController.roomDepth * RoomEditorController.cellSize;
    final wallZ = -roomDepth / 2;
    final backdropZ = wallZ - 46;
    final celestialZ = wallZ - 44.5;
    final farHillZ = wallZ - 25;
    final nearHillZ = wallZ - 16;
    final treeZ = wallZ - 10;
    final look = _skyLook(time, weather);
    _activeSkyLook = look;

    const skyW = 220.0;
    const skyH = 72.0;
    const bottomY = -22.0;
    const bands = 20;
    final backdropCenterX = _windowProjectionCenterX(backdropZ, wallZ);
    final bandH = skyH / bands;
    for (var i = 0; i < bands; i += 1) {
      final f = (i + 0.5) / bands; // 0 at the horizon, 1 at the zenith
      group.add(
        _skyPanel(
          width: skyW,
          height: bandH + 0.04,
          color: _lerpColor(look.horizon, look.zenith, f),
          x: backdropCenterX,
          y: bottomY + (i + 0.5) * bandH,
          z: backdropZ,
        ),
      );
    }

    // A broad low-altitude glow makes dawn and dusk legible even when the
    // actual disc is partially hidden by the hills.
    group.add(
      _skyPanel(
        width: 180,
        height: 6.5,
        color: look.horizonGlow,
        x: backdropCenterX,
        y: 2.1,
        z: backdropZ + 0.2,
        opacity: 0.08 + look.twilightStrength * 0.3,
      ),
    );

    if (look.isNight) {
      for (var star = 0; star < 90; star += 1) {
        final sx = backdropCenterX + (((star * 53) % 211) / 211.0 - 0.5) * 180;
        final sy = 2.5 + (((star * 31) % 97) / 97.0) * 16;
        group.add(
          _skyDisc(
            radius: 0.07 + ((star * 17) % 4) * 0.025,
            color: 0xF2F4FA,
            x: sx,
            y: sy,
            z: backdropZ + 0.45,
            opacity: 0.5 + ((star * 13) % 5) * 0.09,
          ),
        );
      }
    }

    _skySun = _buildCelestialBody(
      coreColor: look.sun,
      haloColor: look.sun,
      coreRadius: 1.25,
      haloRadius: 3.8,
      opacity: look.celestialOpacity,
    )..position.z = celestialZ;
    _skyMoon = _buildCelestialBody(
      coreColor: look.moon,
      haloColor: 0xBFCFF2,
      coreRadius: 1.05,
      haloRadius: 2.8,
      opacity: look.celestialOpacity * 0.9,
    )..position.z = celestialZ + 0.1;
    group
      ..add(_skySun!)
      ..add(_skyMoon!);
    _positionCelestialBodies(time);

    for (var cloudIndex = 0; cloudIndex < look.clouds; cloudIndex += 1) {
      final farLayer = cloudIndex.isEven;
      final cloudZ = wallZ - (farLayer ? 33.0 : 28.0);
      final cloudCenterX = _windowProjectionCenterX(cloudZ, wallZ);
      final spread = farLayer ? 112.0 : 92.0;
      final cloud =
          _buildCloud(
              scale: (farLayer ? 2.1 : 1.7) + (cloudIndex % 3) * 0.2,
              color: look.cloudColor,
              shadowColor: look.cloudShadow,
              opacity: look.cloudOpacity,
            )
            ..position.setValues(
              cloudCenterX + (((cloudIndex * 37) % 101) / 101.0 - 0.5) * spread,
              5.5 + (((cloudIndex * 61) % 97) / 97.0) * 8.5,
              cloudZ,
            );
      group.add(cloud);
      _skyCloudGroups.add(cloud);
    }

    _addLandscape(group, wallZ, farHillZ, nearHillZ, treeZ, look);

    if (look.rain) {
      final rainZ = wallZ - 2.2;
      final rainCenterX = _windowProjectionCenterX(rainZ, wallZ);
      for (var rainIndex = 0; rainIndex < 58; rainIndex += 1) {
        final drop = _skyPanel(
          width: 0.035,
          height: 0.55 + (rainIndex % 4) * 0.12,
          depth: 0.025,
          color: 0xC5D1DD,
          x: rainCenterX + (((rainIndex * 29) % 103) / 103.0 - 0.5) * 9.5,
          y: -0.8 + (((rainIndex * 71) % 107) / 107.0) * 8.8,
          z: rainZ - (rainIndex % 4) * 0.35,
          opacity: 0.35 + (rainIndex % 3) * 0.1,
        )..rotation.z = -0.14;
        group.add(drop);
        _skyRainDrops.add(drop);
      }
    }

    return group;
  }

  double _windowProjectionCenterX(double z, double wallZ) {
    const windowCenterX = 1.0;
    return windowCenterX * (z / wallZ);
  }

  three.Group _buildCelestialBody({
    required int coreColor,
    required int haloColor,
    required double coreRadius,
    required double haloRadius,
    required double opacity,
  }) {
    final body = three.Group();
    body.add(
      _skyDisc(radius: haloRadius, color: haloColor, opacity: opacity * 0.14),
    );
    body.add(
      _skyDisc(
        radius: haloRadius * 0.58,
        color: haloColor,
        z: 0.08,
        opacity: opacity * 0.24,
      ),
    );
    body.add(
      _skyDisc(radius: coreRadius, color: coreColor, z: 0.16, opacity: opacity),
    );
    return body;
  }

  void _positionCelestialBodies(double time) {
    final look = _activeSkyLook;
    final sun = _skySun;
    final moon = _skyMoon;
    if (look == null || sun == null || moon == null) {
      return;
    }

    final roomDepth =
        RoomEditorController.roomDepth * RoomEditorController.cellSize;
    final wallZ = -roomDepth / 2;
    final celestialZ = wallZ - 44.5;
    final centerX = _windowProjectionCenterX(celestialZ, wallZ);
    const horizonY = _eyeHeight;
    const horizontalRadius = 15.0;
    const verticalRadius = 11.5;

    final sunArc = skyCelestialArc(time);
    sun
      ..visible = look.celestialOpacity > 0.01 && sunArc.altitude > -0.055
      ..position.x = centerX + sunArc.horizontal * horizontalRadius
      ..position.y = horizonY + sunArc.altitude * verticalRadius;

    final moonArc = skyCelestialArc(time, moon: true);
    moon
      ..visible = look.celestialOpacity > 0.01 && moonArc.altitude > -0.055
      ..position.x = centerX + moonArc.horizontal * horizontalRadius
      ..position.y = horizonY + moonArc.altitude * verticalRadius;
  }

  three.Group _buildCloud({
    required double scale,
    required int color,
    required int shadowColor,
    required double opacity,
  }) {
    final cloud = three.Group();
    for (final shadow in const [
      (dx: -0.9, dy: -0.22, r: 0.78),
      (dx: 0.0, dy: -0.32, r: 1.08),
      (dx: 1.0, dy: -0.22, r: 0.76),
    ]) {
      cloud.add(
        _skyDisc(
          radius: shadow.r * scale,
          color: shadowColor,
          x: shadow.dx * scale,
          y: shadow.dy * scale,
          opacity: opacity * 0.78,
        ),
      );
    }
    for (final puff in const [
      (dx: -1.0, dy: 0.0, r: 0.78),
      (dx: 0.0, dy: 0.08, r: 1.08),
      (dx: 1.05, dy: -0.04, r: 0.82),
      (dx: 0.35, dy: 0.52, r: 0.72),
      (dx: -0.42, dy: 0.42, r: 0.62),
    ]) {
      cloud.add(
        _skyDisc(
          radius: puff.r * scale,
          color: color,
          x: puff.dx * scale,
          y: puff.dy * scale,
          z: 0.18,
          opacity: opacity,
        ),
      );
    }
    return cloud;
  }

  void _addLandscape(
    three.Group group,
    double wallZ,
    double farHillZ,
    double nearHillZ,
    double treeZ,
    _SkyLook look,
  ) {
    final farCenterX = _windowProjectionCenterX(farHillZ, wallZ);
    for (final hill in const [
      (dx: -54.0, y: -1.5, w: 22.0, h: 8.6),
      (dx: -39.0, y: -1.1, w: 24.0, h: 9.2),
      (dx: -20.0, y: -1.8, w: 18.0, h: 8.0),
      (dx: -9.5, y: -1.2, w: 21.0, h: 9.5),
      (dx: 2.0, y: -1.6, w: 18.0, h: 8.2),
      (dx: 13.0, y: -1.0, w: 22.0, h: 9.2),
      (dx: 25.0, y: -1.7, w: 18.0, h: 7.8),
      (dx: 40.0, y: -1.2, w: 23.0, h: 9.0),
      (dx: 55.0, y: -1.7, w: 21.0, h: 8.1),
    ]) {
      group.add(
        _skyOval(
          width: hill.w,
          height: hill.h,
          color: look.farHills,
          x: farCenterX + hill.dx,
          y: hill.y,
          z: farHillZ,
        ),
      );
    }

    final nearCenterX = _windowProjectionCenterX(nearHillZ, wallZ);
    for (final hill in const [
      (dx: -43.0, y: -1.7, w: 19.0, h: 7.8),
      (dx: -29.0, y: -1.3, w: 20.0, h: 8.2),
      (dx: -16.0, y: -2.0, w: 15.0, h: 7.4),
      (dx: -6.0, y: -1.55, w: 18.0, h: 8.0),
      (dx: 5.0, y: -2.0, w: 16.0, h: 7.2),
      (dx: 15.0, y: -1.4, w: 18.0, h: 8.4),
      (dx: 29.0, y: -1.7, w: 20.0, h: 7.9),
      (dx: 43.0, y: -1.35, w: 19.0, h: 8.3),
    ]) {
      group.add(
        _skyOval(
          width: hill.w,
          height: hill.h,
          color: look.nearHills,
          x: nearCenterX + hill.dx,
          y: hill.y,
          z: nearHillZ,
        ),
      );
    }
    group.add(
      _skyPanel(
        width: 120,
        height: 12,
        color: look.nearHills,
        x: nearCenterX,
        y: -7.0,
        z: nearHillZ + 0.15,
      ),
    );

    final treeCenterX = _windowProjectionCenterX(treeZ, wallZ);
    for (var treeIndex = 0; treeIndex < 32; treeIndex += 1) {
      final scale = 0.72 + ((treeIndex * 17) % 7) * 0.08;
      _addTree(
        group,
        x: treeCenterX + (((treeIndex * 43) % 101) / 101.0 - 0.5) * 52,
        baseY: -0.35 + (treeIndex % 3) * 0.12,
        z: treeZ - (treeIndex % 4) * 0.42,
        scale: scale,
        trunkColor: look.treeTrunk,
        canopyColor: look.trees,
      );
    }
  }

  void _addTree(
    three.Group group, {
    required double x,
    required double baseY,
    required double z,
    required double scale,
    required int trunkColor,
    required int canopyColor,
  }) {
    group.add(
      _skyPanel(
        width: 0.34 * scale,
        height: 2.25 * scale,
        depth: 0.24,
        color: trunkColor,
        x: x,
        y: baseY + 1.1 * scale,
        z: z,
      ),
    );
    for (final canopy in const [
      (dx: -0.65, dy: 2.35, size: 1.45),
      (dx: 0.58, dy: 2.45, size: 1.35),
      (dx: 0.0, dy: 3.25, size: 1.65),
    ]) {
      group.add(
        _skyOval(
          width: canopy.size * 1.55 * scale,
          height: canopy.size * 1.35 * scale,
          color: canopyColor,
          x: x + canopy.dx * scale,
          y: baseY + canopy.dy * scale,
          z: z + 0.1,
        ),
      );
    }
  }

  _SkyLook _skyLook(double time, SkyWeather weather) {
    // Anchor palettes (RGB) around the day; interpolate between the two nearest.
    const anchors = [
      (t: 0.0, zenith: 0x070B18, horizon: 0x141D33, sun: 0xE6EBF5),
      (t: 0.20, zenith: 0x17213C, horizon: 0x463B5B, sun: 0xFFB58A),
      (t: 0.245, zenith: 0x3D4A78, horizon: 0xC56C62, sun: 0xFFB36B),
      (t: 0.285, zenith: 0x6682B5, horizon: 0xF5B276, sun: 0xFFD49C),
      (t: 0.50, zenith: 0x3F86CF, horizon: 0xA7D2EF, sun: 0xFFF3D4),
      (t: 0.68, zenith: 0x5881AE, horizon: 0xF2B16E, sun: 0xFFD28A),
      (t: 0.735, zenith: 0x51456F, horizon: 0xE06F4E, sun: 0xFF9954),
      (t: 0.79, zenith: 0x202743, horizon: 0x59405D, sun: 0xFF8A5C),
      (t: 1.0, zenith: 0x070B18, horizon: 0x141D33, sun: 0xE6EBF5),
    ];
    var lo = anchors.first;
    var hi = anchors.last;
    for (var i = 0; i < anchors.length - 1; i += 1) {
      if (time >= anchors[i].t && time <= anchors[i + 1].t) {
        lo = anchors[i];
        hi = anchors[i + 1];
        break;
      }
    }
    final span = hi.t - lo.t;
    final f = span <= 0 ? 0.0 : (time - lo.t) / span;
    var zenith = _lerpColor(lo.zenith, hi.zenith, f);
    var horizon = _lerpColor(lo.horizon, hi.horizon, f);
    final sun = _lerpColor(lo.sun, hi.sun, f);
    final sunArc = skyCelestialArc(time);
    final isNight = sunArc.altitude <= -0.05;
    final daylight = ((sunArc.altitude + 0.12) / 1.12)
        .clamp(0.0, 1.0)
        .toDouble();
    double cyclicDistance(double a, double b) {
      final direct = (a - b).abs();
      return math.min(direct, 1 - direct);
    }

    final twilightStrength = math.max(
      (1 - cyclicDistance(time, 0.25) / 0.085).clamp(0.0, 1.0),
      (1 - cyclicDistance(time, 0.75) / 0.085).clamp(0.0, 1.0),
    );
    var horizonGlow = _lerpColor(0x718DAD, sun, twilightStrength);
    var farHills = _lerpColor(0x17243A, 0x6F8792, daylight);
    var nearHills = _lerpColor(0x111B2B, 0x3F6157, daylight);
    var trees = _lerpColor(0x0A1220, 0x29483E, daylight);
    var treeTrunk = _lerpColor(0x080D17, 0x302E28, daylight);

    var clouds = 2;
    var rain = false;
    var cloudColor = 0xF4F1EC;
    var cloudShadow = 0xC5CBD2;
    var cloudOpacity = 0.72;
    var celestialOpacity = 1.0;
    switch (weather) {
      case SkyWeather.clear:
        clouds = 2;
        cloudOpacity = 0.58;
      case SkyWeather.cloudy:
        clouds = 6;
        cloudColor = 0xF0ECE6;
        cloudShadow = 0xB0B6BD;
        cloudOpacity = 0.82;
        celestialOpacity = 0.82;
        zenith = _lerpColor(zenith, 0x9AA3AD, 0.25);
        horizon = _lerpColor(horizon, 0xB8BEC6, 0.25);
      case SkyWeather.overcast:
        clouds = 10;
        cloudColor = 0xAFB4BB;
        cloudShadow = 0x858B92;
        cloudOpacity = 0.92;
        celestialOpacity = 0.12;
        zenith = _lerpColor(zenith, 0x8C9298, 0.6);
        horizon = _lerpColor(horizon, 0xA2A7AD, 0.6);
        horizonGlow = _lerpColor(horizonGlow, 0xA7ACB2, 0.72);
        farHills = _lerpColor(farHills, 0x68737B, 0.5);
        nearHills = _lerpColor(nearHills, 0x47545A, 0.45);
      case SkyWeather.rain:
        clouds = 9;
        rain = true;
        cloudColor = 0x7E848C;
        cloudShadow = 0x555B63;
        cloudOpacity = 0.96;
        celestialOpacity = 0;
        zenith = _lerpColor(zenith, 0x5C6066, 0.65);
        horizon = _lerpColor(horizon, 0x6E7378, 0.65);
        horizonGlow = _lerpColor(horizonGlow, 0x737A82, 0.8);
        farHills = _lerpColor(farHills, 0x48545B, 0.65);
        nearHills = _lerpColor(nearHills, 0x313F43, 0.62);
        trees = _lerpColor(trees, 0x1F2D2F, 0.58);
        treeTrunk = _lerpColor(treeTrunk, 0x1D2425, 0.58);
    }

    return _SkyLook(
      zenith: zenith,
      horizon: horizon,
      horizonGlow: horizonGlow,
      sun: sun,
      moon: 0xE8EEFF,
      isNight: isNight,
      twilightStrength: twilightStrength,
      celestialOpacity: celestialOpacity,
      clouds: clouds,
      cloudColor: cloudColor,
      cloudShadow: cloudShadow,
      cloudOpacity: cloudOpacity,
      rain: rain,
      farHills: farHills,
      nearHills: nearHills,
      trees: trees,
      treeTrunk: treeTrunk,
    );
  }

  int _lerpColor(int a, int b, double t) {
    final tt = t.clamp(0.0, 1.0);
    int channel(int shift) {
      final ca = (a >> shift) & 0xff;
      final cb = (b >> shift) & 0xff;
      return (ca + (cb - ca) * tt).round().clamp(0, 255);
    }

    return (channel(16) << 16) | (channel(8) << 8) | channel(0);
  }

  three.Mesh _skyPanel({
    required double width,
    required double height,
    required int color,
    double depth = 0.05,
    double x = 0,
    double y = 0,
    double z = 0,
    double opacity = 1.0,
  }) {
    return three.Mesh(
      three.BoxGeometry(width, height, depth),
      three.MeshBasicMaterial.fromMap({
        'color': color & 0x00ffffff,
        if (opacity < 1.0) 'transparent': true,
        if (opacity < 1.0) 'opacity': opacity,
      }),
    )..position.setValues(x, y, z);
  }

  three.Mesh _skyDisc({
    required double radius,
    required int color,
    double x = 0,
    double y = 0,
    double z = 0,
    double opacity = 1.0,
  }) {
    return three.Mesh(
      three.SphereGeometry(radius, 18, 18),
      three.MeshBasicMaterial.fromMap({
        'color': color & 0x00ffffff,
        if (opacity < 1.0) 'transparent': true,
        if (opacity < 1.0) 'opacity': opacity,
      }),
    )..position.setValues(x, y, z);
  }

  three.Mesh _skyOval({
    required double width,
    required double height,
    required int color,
    double x = 0,
    double y = 0,
    double z = 0,
    double opacity = 1.0,
  }) {
    return three.Mesh(
        three.SphereGeometry(1, 24, 16),
        three.MeshBasicMaterial.fromMap({
          'color': color & 0x00ffffff,
          if (opacity < 1.0) 'transparent': true,
          if (opacity < 1.0) 'opacity': opacity,
        }),
      )
      ..scale.setValues(width / 2, height / 2, 0.35)
      ..position.setValues(x, y, z);
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

    // Invisible hit box around the radio so tapping it opens the music picker.
    // A touch larger than the body, and resolved with priority over the desk
    // tap target it sits inside (see _onPointerDown).
    _addRoomTapTarget(
      scene,
      target: _RoomTapTarget.radio,
      width: 0.92,
      height: 0.6,
      depth: 0.5,
      x: 1.52,
      y: 1.12,
      z: deskZ + 0.05,
    );

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
    final pointerId = (event.pointerId as num).toInt();
    _activePointers.add(pointerId);
    _activePointerPositions[pointerId] = Offset(
      _eventClientX(event),
      _eventClientY(event),
    );
    if (_isPinching) {
      // More than one finger is a gesture, not a drag/tilt.
      _multiTouchSequenceActive = true;
      _cancelPendingRoomTap();
      _cancelInteraction();
      return;
    }
    _recordPointerPosition(event, isDown: true);
    _pendingTapTarget = null;
    _pendingTapAnchor = null;
    _pendingFurnitureTapItemId = null;
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
        // The radio hit box sits inside the larger desk hit box, so prefer the
        // radio when the ray passes through it; otherwise take the nearest hit.
        for (final hit in roomIntersections) {
          final resolved = _resolveRoomTapTarget(hit.object);
          if (resolved == null) {
            continue;
          }
          _pendingTapTarget ??= resolved;
          _pendingTapAnchor ??= hit.point?.clone();
          if (resolved == _RoomTapTarget.radio) {
            _pendingTapTarget = resolved;
            _pendingTapAnchor = hit.point?.clone();
            break;
          }
        }
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
      _beginCameraTiltCandidate(event);
      return;
    }

    final placed = widget.controller.placedItemById(sceneFurniture.itemId);
    if (placed != null) {
      _pendingTapTarget = _tapTargetForDefinition(
        widget.controller.definitionFor(placed.definitionId),
      );
      _pendingTapAnchor = intersections.first.point?.clone();
    }

    if (!widget.canMoveFurniture ||
        widget.controller.selectedItemId != sceneFurniture.itemId) {
      if (widget.canMoveFurniture) {
        _pendingFurnitureTapItemId = sceneFurniture.itemId;
      }
      _beginCameraTiltCandidate(event);
      return;
    }

    if (widget.rotateSelectedWithDrag) {
      _activeRotationItemId = sceneFurniture.itemId;
      _rotationDragLastX = _eventClientX(event);
      return;
    }

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
    if (_isPinching) {
      _activePointerPositions[(event.pointerId as num).toInt()] = Offset(
        _eventClientX(event),
        _eventClientY(event),
      );
      if (_isCameraHeightPanning) {
        _updateCameraHeightPan();
      } else if (_isCameraPanning) {
        _updateCameraPan();
      } else {
        _lastPanCentroid = null;
      }
      return;
    }
    _recordPointerPosition(event, isDown: false);
    if (_pointerTravel > 10) {
      _pendingTapTarget = null;
      _pendingFurnitureTapItemId = null;
    }

    if (_activeRotationItemId != null) {
      final x = _eventClientX(event);
      final deltaX = x - _rotationDragLastX;
      _rotationDragLastX = x;
      if (deltaX.abs() > 0.1) {
        widget.onRotateSelectedBy?.call(deltaX * _rotationDragDegreesPerPixel);
      }
      return;
    }

    if (_activeDragItemId == null) {
      _updateCameraTilt(event);
      return;
    }

    _updateDragPreview(event);
  }

  bool _updateDragPreview(dynamic event) {
    final placed = widget.controller.placedItemById(_activeDragItemId!);
    if (placed == null) {
      return false;
    }

    _updatePointer(event);
    _raycaster.setFromCamera(_pointer, _camera);

    if (_raycaster.ray.intersectPlane(_dragPlane, _dragIntersection) == null) {
      return false;
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
    return true;
  }

  void _onPointerUp([dynamic event]) {
    if (event != null) {
      final pointerId = (event.pointerId as num).toInt();
      _activePointers.remove(pointerId);
      _activePointerPositions.remove(pointerId);
      _lastPanCentroid = _isCameraPanning
          ? _pointerCentroid(minPointers: _cameraPanPointerCount)
          : null;
      _recordPointerPosition(event, isDown: false);
    }

    if (_multiTouchSequenceActive) {
      _pendingTapTarget = null;
      _pendingTapAnchor = null;
      _pendingFurnitureTapItemId = null;
      _cameraTiltCandidate = false;
      _cameraTiltActive = false;
      if (_activePointers.isEmpty) {
        _multiTouchSequenceActive = false;
      }
      return;
    }

    final tapTarget = _pointerTravel <= 10 ? _pendingTapTarget : null;
    final tapAnchor = _pointerTravel <= 10 ? _pendingTapAnchor : null;
    final furnitureTapItemId = _pointerTravel <= 10
        ? _pendingFurnitureTapItemId
        : null;

    if (_activeRotationItemId != null) {
      _activeRotationItemId = null;
      _pendingTapTarget = null;
      _pendingFurnitureTapItemId = null;
      _cameraTiltCandidate = false;
      _cameraTiltActive = false;
      return;
    }

    if (_activeDragItemId == null) {
      final wasTilting = _cameraTiltActive;
      _cameraTiltCandidate = false;
      _cameraTiltActive = false;
      _pendingTapTarget = null;
      _pendingFurnitureTapItemId = null;
      if (wasTilting) {
        return;
      }
      if (furnitureTapItemId != null) {
        widget.controller.selectItem(furnitureTapItemId);
        return;
      }
      _resolveRoomTapGesture(tapTarget, tapAnchor);
      return;
    }

    if (event != null) {
      _updateDragPreview(event);
    }
    if (_dragPreviewOrigin != null && _dragPreviewValid) {
      widget.controller.movePlacedItem(_activeDragItemId!, _dragPreviewOrigin!);
    }

    _activeDragItemId = null;
    _dragPreviewOrigin = null;
    _dragPreviewValid = true;
    _pendingTapTarget = null;
    _pendingFurnitureTapItemId = null;
    _cameraTiltCandidate = false;
    _cameraTiltActive = false;
    _syncSceneWithController();
    _resolveRoomTapGesture(tapTarget, tapAnchor);
  }

  void _beginCameraTiltCandidate(dynamic event) {
    _cameraTiltCandidate = true;
    _cameraTiltActive = false;
    _cameraYaw = widget.outsideView
        ? clampOutwardCameraYaw(_currentCameraYaw)
        : _currentCameraYaw;
    _cameraPitch = _currentCameraPitch;
    _yawAtDragStart = _cameraYaw;
    _pitchAtDragStart = _cameraPitch;
    _deskYawAtDragStart = _deskYaw;
    _deskPitchAtDragStart = _deskPitch;
    _cameraTiltPointerStartX = _eventClientX(event);
    _cameraTiltPointerStartY = _eventClientY(event);
  }

  void _updateCameraTilt(dynamic event) {
    // Night mode is a fixed shot behind the good-night overlay, so it stays
    // locked. The desk view allows a limited seated look (handled below).
    if (!_cameraTiltCandidate || widget.nightMode) {
      return;
    }

    final deltaX = _eventClientX(event) - _cameraTiltPointerStartX;
    final deltaY = _eventClientY(event) - _cameraTiltPointerStartY;
    final travel = math.sqrt(deltaX * deltaX + deltaY * deltaY);
    if (!_cameraTiltActive && travel < _cameraTiltStartThreshold) {
      return;
    }

    _cameraTiltActive = true;
    _pendingTapTarget = null;

    if (widget.deskFocused) {
      // Seated: pan the gaze within the front hemisphere only, eye fixed.
      _deskYaw =
          (_deskYawAtDragStart -
                  deltaX * _yawSensitivity * widget.cameraRotateSensitivity)
              .clamp(-_deskYawLimit, _deskYawLimit)
              .toDouble();
      _deskPitch =
          (_deskPitchAtDragStart +
                  deltaY * _pitchSensitivity * widget.cameraRotateSensitivity)
              .clamp(_deskPitchMin, _deskPitchMax)
              .toDouble();
      _refreshCamera();
      return;
    }

    final requestedYaw =
        _yawAtDragStart -
        deltaX * _yawSensitivity * widget.cameraRotateSensitivity;
    _cameraYaw = widget.outsideView
        ? clampOutwardCameraYaw(requestedYaw)
        : _normalizeRadians(requestedYaw);
    _cameraPitch =
        (_pitchAtDragStart +
                deltaY * _pitchSensitivity * widget.cameraRotateSensitivity)
            .clamp(
              widget.outsideView ? _outsidePitchMin : _minLookPitch,
              widget.outsideView ? _outsidePitchMax : _maxLookPitch,
            )
            .toDouble();
    _refreshCamera();
  }

  void _updateCameraPan() {
    if (widget.deskFocused || widget.nightMode || widget.outsideView) {
      _lastPanCentroid = null;
      return;
    }

    final centroid = _pointerCentroid(minPointers: 3);
    final lastCentroid = _lastPanCentroid;
    _lastPanCentroid = centroid;
    if (centroid == null || lastCentroid == null) {
      return;
    }

    final delta = centroid - lastCentroid;
    if (delta.distanceSquared < 0.01) {
      return;
    }

    final rightX = math.cos(_cameraYaw);
    final rightZ = math.sin(_cameraYaw);
    final forwardX = math.sin(_cameraYaw);
    final forwardZ = -math.cos(_cameraYaw);
    final panX =
        (-delta.dx * rightX + delta.dy * forwardX) * _cameraPanUnitsPerPixel;
    final panZ =
        (-delta.dx * rightZ + delta.dy * forwardZ) * _cameraPanUnitsPerPixel;
    final maxPanX =
        RoomEditorController.roomWidth * RoomEditorController.cellSize / 2 -
        _cameraPanWallPaddingX;
    final maxPanZ =
        RoomEditorController.roomDepth * RoomEditorController.cellSize / 2 -
        _cameraPanWallPaddingZ;

    final targetX = (_cameraPanOffset.x + panX)
        .clamp(-maxPanX, maxPanX)
        .toDouble();
    final targetZ = (_cameraPanOffset.z + panZ)
        .clamp(-maxPanZ, maxPanZ)
        .toDouble();

    // Move each axis independently, accepting it only if the eye wouldn't end
    // up inside a piece of furniture. This lets the camera slide along an edge
    // instead of passing through — you go around furniture, never into it.
    final cameraY = _eyeHeight + _cameraPanOffset.y;
    if (!_isEyeBlocked(targetX, cameraY, _cameraPanOffset.z)) {
      _cameraPanOffset.x = targetX;
    }
    if (!_isEyeBlocked(_cameraPanOffset.x, cameraY, targetZ)) {
      _cameraPanOffset.z = targetZ;
    }
    _refreshCamera();
  }

  /// Whether the camera sphere at world (x, y, z) overlaps furniture.
  bool _isEyeBlocked(double x, double y, double z) {
    for (final item in widget.controller.placedItems) {
      final colliderHeight = _colliderHeightForDefinition(item.definitionId);
      if (y - _cameraColliderRadius >= colliderHeight) {
        continue;
      }
      final footprint = widget.controller.footprintForDefinition(
        item.definitionId,
        item.rotationQuarterTurns,
      );
      final center = _gridOriginToWorld(
        definitionId: item.definitionId,
        quarterTurns: item.rotationQuarterTurns,
        origin: item.origin,
      );
      final halfWidth =
          footprint.width * RoomEditorController.cellSize / 2 +
          _cameraColliderRadius;
      final halfDepth =
          footprint.depth * RoomEditorController.cellSize / 2 +
          _cameraColliderRadius;
      if ((x - center.x).abs() < halfWidth &&
          (z - center.z).abs() < halfDepth) {
        return true;
      }
    }

    for (final sofa in _sofaColliders) {
      final overlapsVertically =
          y + _cameraColliderRadius > sofa.minY &&
          y - _cameraColliderRadius < sofa.maxY;
      if (overlapsVertically &&
          (x - sofa.centerX).abs() < sofa.halfWidth + _cameraColliderRadius &&
          (z - sofa.centerZ).abs() < sofa.halfDepth + _cameraColliderRadius) {
        return true;
      }
    }

    return false;
  }

  void _updateCameraHeightPan() {
    if (widget.deskFocused || widget.nightMode || widget.outsideView) {
      _lastPanCentroid = null;
      return;
    }

    final centroid = _pointerCentroid(minPointers: 4);
    final lastCentroid = _lastPanCentroid;
    _lastPanCentroid = centroid;
    if (centroid == null || lastCentroid == null) {
      return;
    }

    final delta = centroid - lastCentroid;
    if (delta.distanceSquared < 0.01) {
      return;
    }

    final currentOffsetY = _cameraPanOffset.y;
    final targetOffsetY =
        (currentOffsetY + delta.dy * _cameraHeightPanUnitsPerPixel)
            .clamp(_minCameraHeightOffset, _maxCameraHeightOffset)
            .toDouble();
    final currentY = _eyeHeight + currentOffsetY;
    final targetY = _eyeHeight + targetOffsetY;
    final targetBlocked = _isEyeBlocked(
      _cameraPanOffset.x,
      targetY,
      _cameraPanOffset.z,
    );
    final escapingUpward =
        targetY > currentY &&
        _isEyeBlocked(_cameraPanOffset.x, currentY, _cameraPanOffset.z);
    if (!targetBlocked || escapingUpward) {
      _cameraPanOffset.y = targetOffsetY;
      _refreshCamera();
    }
  }

  Offset? _pointerCentroid({required int minPointers}) {
    if (_activePointerPositions.length < minPointers) {
      return null;
    }

    var x = 0.0;
    var y = 0.0;
    for (final position in _activePointerPositions.values) {
      x += position.dx;
      y += position.dy;
    }
    final count = _activePointerPositions.length;
    return Offset(x / count, y / count);
  }

  void _refreshCamera() {
    if (_threeJs == null) {
      return;
    }
    _configureCamera(_currentViewportSize());
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
        final removedCollider = _furnitureColliderMeshes.remove(instanceId);
        if (removedCollider != null) {
          _threeJs!.scene.remove(removedCollider);
        }
      }
    }

    for (final item in widget.controller.placedItems) {
      _sceneFurniture.putIfAbsent(
        item.instanceId,
        () => _createSceneFurniture(item),
      );
      _furnitureColliderMeshes.putIfAbsent(item.instanceId, () {
        final mesh = _createColliderMesh();
        _threeJs!.scene.add(mesh);
        return mesh;
      });
    }

    for (final item in widget.controller.placedItems) {
      final isDragging = item.instanceId == _activeDragItemId;
      final previewOrigin = isDragging ? _dragPreviewOrigin : null;
      final isValid = isDragging
          ? _dragPreviewValid
          : (!widget.canMoveFurniture ||
                widget.controller.isPlacedItemValid(item.instanceId));
      _updateSceneFurniture(
        item,
        previewOrigin: previewOrigin,
        isDragging: isDragging,
        isValid: isValid,
      );
      _updateFurnitureCollider(item, previewOrigin ?? item.origin);
    }

    if (mounted) {
      setState(() {});
    }
    _publishSelectedScreenPosition();
  }

  three.Mesh _createColliderMesh({
    int color = 0x39d5e8,
    double opacity = 0.24,
  }) {
    final material = three.MeshBasicMaterial.fromMap({
      'color': color,
      'transparent': true,
      'opacity': opacity,
      'depthWrite': false,
    });
    return three.Mesh(three.BoxGeometry(1, 1, 1), material)..renderOrder = 20;
  }

  three.Mesh _createCameraColliderMesh() {
    final material = three.MeshBasicMaterial.fromMap({
      'color': 0xffc857,
      'transparent': true,
      'opacity': 0.32,
      'depthWrite': false,
      'depthTest': false,
      'wireframe': true,
      'side': three.DoubleSide,
    });
    return three.Mesh(
      three.SphereGeometry(_cameraColliderRadius, 16, 10),
      material,
    )..renderOrder = 21;
  }

  three.Line _createDebugCenterRay() {
    final geometry = three.BufferGeometry().setFromPoints([
      three.Vector3.zero(),
      three.Vector3(0, 0, -1),
    ]);
    final material = three.LineBasicMaterial.fromMap({
      'color': 0xff3b30,
      'transparent': true,
      'opacity': 0.9,
      'depthTest': false,
      'depthWrite': false,
    });
    return three.Line(geometry, material)..renderOrder = 22;
  }

  void _updateFurnitureCollider(PlacedRoomItem item, GridPoint origin) {
    final mesh = _furnitureColliderMeshes[item.instanceId];
    if (mesh == null) {
      return;
    }
    final footprint = widget.controller.footprintForDefinition(
      item.definitionId,
      item.rotationQuarterTurns,
    );
    final center = _gridOriginToWorld(
      definitionId: item.definitionId,
      quarterTurns: item.rotationQuarterTurns,
      origin: origin,
    );
    final colliderHeight = _colliderHeightForDefinition(item.definitionId);
    mesh
      ..position.setValues(center.x, colliderHeight / 2, center.z)
      ..scale.setValues(
        footprint.width * RoomEditorController.cellSize,
        colliderHeight,
        footprint.depth * RoomEditorController.cellSize,
      )
      ..visible = widget.showFurnitureColliders;
  }

  double _colliderHeightForDefinition(String definitionId) {
    final definition = widget.controller.definitionFor(definitionId);
    return switch (definition.visualKind) {
      RoomItemVisualKind.bed => _bedColliderHeight,
      _ => _defaultFurnitureColliderHeight,
    };
  }

  void _updateCameraColliderMesh() {
    _cameraColliderMesh?.position.setFrom(_camera.position);
  }

  void _updateDebugCenterRay() {
    final line = _debugCenterRay;
    if (line == null || !widget.showFurnitureColliders) {
      return;
    }
    _camera.updateMatrixWorld(true);
    _raycaster.setFromCamera(three.Vector2.zero(), _camera);
    final colliderMeshes = <three.Object3D>[
      ..._furnitureColliderMeshes.values,
      ..._sofaColliderMeshes,
    ];
    final hits = colliderMeshes.isEmpty
        ? const <three.Intersection>[]
        : _raycaster.intersectObjects(colliderMeshes);
    final length = hits.isEmpty
        ? _debugCenterRayLength
        : math.min(hits.first.distance, _debugCenterRayLength);
    line
      ..position.setFrom(_camera.position)
      ..quaternion.setFrom(_camera.quaternion)
      ..scale.setValues(1, 1, length);
  }

  void _syncColliderVisibility() {
    for (final collider in _furnitureColliderMeshes.values) {
      collider.visible = widget.showFurnitureColliders;
    }
    for (final collider in _sofaColliderMeshes) {
      collider.visible = widget.showFurnitureColliders;
    }
    _cameraColliderMesh?.visible = widget.showFurnitureColliders;
    _debugCenterRay?.visible = widget.showFurnitureColliders;
    _updateDebugCenterRay();
  }

  void _publishSelectedScreenPosition() {
    if (widget.onSelectedScreenPositionChanged == null) {
      return;
    }

    final selectedItemId = widget.controller.selectedItemId;
    final sceneFurniture = selectedItemId == null
        ? null
        : _sceneFurniture[selectedItemId];
    final renderBox =
        _threeJs?.globalKey.currentContext?.findRenderObject() as RenderBox?;
    if (!_sceneReady || sceneFurniture == null || renderBox == null) {
      _notifySelectedScreenPosition(null);
      return;
    }

    _camera.updateMatrixWorld(true);
    final projected = sceneFurniture.root.position.clone()
      ..y += 1.0
      ..project(_camera);
    if (projected.z < -1 || projected.z > 1) {
      _notifySelectedScreenPosition(null);
      return;
    }

    final size = renderBox.size;
    final offset = Offset(
      (projected.x + 1) * 0.5 * size.width,
      (-projected.y + 1) * 0.5 * size.height,
    );
    _notifySelectedScreenPosition(offset);
  }

  void _notifySelectedScreenPosition(Offset? offset) {
    final last = _lastSelectedScreenPosition;
    if ((last == null && offset == null) ||
        (last != null && offset != null && (last - offset).distance < 1)) {
      return;
    }
    _lastSelectedScreenPosition = offset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onSelectedScreenPositionChanged?.call(offset);
    });
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
    final visualRoot = _buildFurnitureVisual(definition);
    root.add(selectionPlate);
    root.add(visualRoot);
    _threeJs!.scene.add(root);

    return _SceneFurniture(
      itemId: item.instanceId,
      root: root,
      visualRoot: visualRoot,
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
    sceneFurniture.root.rotation.y = item.rotationDegrees * math.pi / 180;

    final isSelected =
        widget.controller.selectedItemId == item.instanceId || isDragging;
    final darkenVisual = widget.canMoveFurniture && isSelected;
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
    _setFurnitureVisualDarkened(sceneFurniture.visualRoot, darkenVisual);
  }

  void _setFurnitureVisualDarkened(three.Object3D root, bool darkened) {
    root.traverse((object) {
      if (object is! three.Mesh || object.material == null) {
        return;
      }
      final material = object.material!;
      final baseColor =
          material.userData['roomBaseColor'] as int? ?? material.color.getHex();
      material.userData['roomBaseColor'] = baseColor;
      material.color = three.Color.fromHex32(
        darkened ? _scaledHexColor(baseColor, 0.42) : baseColor,
      );
      material.needsUpdate = true;
    });
  }

  int _scaledHexColor(int color, double scale) {
    final r = (((color >> 16) & 0xff) * scale).round().clamp(0, 255);
    final g = (((color >> 8) & 0xff) * scale).round().clamp(0, 255);
    final b = ((color & 0xff) * scale).round().clamp(0, 255);
    return (r << 16) | (g << 8) | b;
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

  void _resolveRoomTapGesture(_RoomTapTarget? target, [three.Vector3? anchor]) {
    if (!_delaysRoomTapActions) {
      _handleRoomTapTarget(target, anchor);
      return;
    }

    if (_pendingRoomTapTimer?.isActive ?? false) {
      _cancelPendingRoomTap();
      widget.onDoubleTapRoom?.call();
      return;
    }

    _pendingRoomTapTimer = Timer(_roomTapDoubleTapDebounce, () {
      _pendingRoomTapTimer = null;
      if (!mounted) {
        return;
      }
      _handleRoomTapTarget(target, anchor);
    });
  }

  void _cancelPendingRoomTap() {
    _pendingRoomTapTimer?.cancel();
    _pendingRoomTapTimer = null;
  }

  void _handleRoomTapTarget(_RoomTapTarget? target, [three.Vector3? anchor]) {
    // Resolve beds to their centre rather than preserving the surface point
    // under the finger. That gives every bed tap the same flight destination.
    // Set it before the callback flips deskFocused/nightMode, which triggers
    // _configureCamera on the next build.
    _focusAnchor = _focusAnchorForTapTarget(target, anchor);
    switch (target) {
      case _RoomTapTarget.desk:
        widget.onTapDesk?.call();
        return;
      case _RoomTapTarget.bed:
        widget.onTapBed?.call();
        return;
      case _RoomTapTarget.radio:
        widget.onTapRadio?.call();
        return;
      case _RoomTapTarget.window:
        if (!widget.deskFocused && !widget.nightMode && !widget.outsideView) {
          widget.onTapWindow?.call();
        }
        return;
      case null:
        return;
    }
  }

  three.Vector3? _focusAnchorForTapTarget(
    _RoomTapTarget? target,
    three.Vector3? tapAnchor,
  ) {
    if (target != _RoomTapTarget.bed) {
      return tapAnchor?.clone();
    }

    three.Vector3? nearestBedCenter;
    var nearestDistanceSquared = double.infinity;
    for (final bed in widget.controller.placedItems) {
      if (widget.controller.definitionFor(bed.definitionId).visualKind !=
          RoomItemVisualKind.bed) {
        continue;
      }
      final bedCenter = _gridOriginToWorld(
        definitionId: bed.definitionId,
        quarterTurns: bed.rotationQuarterTurns,
        origin: bed.origin,
      );
      final distanceSquared = tapAnchor == null
          ? 0.0
          : (bedCenter.x - tapAnchor.x) * (bedCenter.x - tapAnchor.x) +
                (bedCenter.z - tapAnchor.z) * (bedCenter.z - tapAnchor.z);
      if (distanceSquared < nearestDistanceSquared) {
        nearestBedCenter = bedCenter;
        nearestDistanceSquared = distanceSquared;
      }
    }
    return nearestBedCenter ?? tapAnchor?.clone();
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
        (x + roomWidth / 2 - footprint.width / 2) /
        RoomEditorController.cellSize;
    final snappedZ =
        (z + roomDepth / 2 - footprint.depth / 2) /
        RoomEditorController.cellSize;

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

  // Geometry lives in furniture_models.dart so the shop's 3D previews build the
  // exact same pieces this room places.
  three.Group _buildFurnitureVisual(RoomItemDefinition definition) {
    return buildFurnitureVisualFor(definition);
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
    return furnitureBox(
      width: width,
      height: height,
      depth: depth,
      color: color,
      x: x,
      y: y,
      z: z,
      castShadow: castShadow,
      receiveShadow: receiveShadow,
    );
  }

  int _hex(Color color) => furnitureHex(color);

  Future<void> _yieldSceneStep() => Future<void>.delayed(Duration.zero);

  void _syncSceneVisibility() {
    final threeJs = _threeJs;
    if (threeJs == null) {
      return;
    }

    threeJs.visible = widget.isActive;
  }
}

class _SkyLook {
  const _SkyLook({
    required this.zenith,
    required this.horizon,
    required this.horizonGlow,
    required this.sun,
    required this.moon,
    required this.isNight,
    required this.twilightStrength,
    required this.celestialOpacity,
    required this.clouds,
    required this.cloudColor,
    required this.cloudShadow,
    required this.cloudOpacity,
    required this.rain,
    required this.farHills,
    required this.nearHills,
    required this.trees,
    required this.treeTrunk,
  });

  final int zenith;
  final int horizon;
  final int horizonGlow;
  final int sun;
  final int moon;
  final bool isNight;
  final double twilightStrength;
  final double celestialOpacity;
  final int clouds;
  final int cloudColor;
  final int cloudShadow;
  final double cloudOpacity;
  final bool rain;
  final int farHills;
  final int nearHills;
  final int trees;
  final int treeTrunk;
}

class _SceneFurniture {
  const _SceneFurniture({
    required this.itemId,
    required this.root,
    required this.visualRoot,
    required this.selectionMaterial,
  });

  final String itemId;
  final three.Group root;
  final three.Group visualRoot;
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
