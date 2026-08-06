import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

import 'furniture_models.dart';
import 'room_gl_gate.dart';
import 'room_state.dart';
import 'room_visuals.dart';

/// Real 3D previews for the shop, built from the same geometry the room places.
///
/// The app can only hold one GL context (see [RoomGlGate]), so a grid of live
/// 3D views is off the table. Instead one renderer does double duty: on startup
/// it renders every catalog piece into an offscreen target and reads the pixels
/// back into cached images for the cards, then stays live as the turntable
/// panel at the top of the shop.

/// Baked card thumbnails, kept for the life of the app.
///
/// Seven pieces at 208px square is roughly 1.2 MB of image cache — cheap enough
/// to hold onto so re-entering the shop is instant and the bake only ever runs
/// once per launch.
class FurnitureThumbnails {
  FurnitureThumbnails._();

  static final FurnitureThumbnails instance = FurnitureThumbnails._();

  /// Bumped whenever a new thumbnail lands, so cards can rebuild as they arrive.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Map<RoomItemVisualKind, ui.Image> _baked =
      <RoomItemVisualKind, ui.Image>{};

  ui.Image? imageFor(RoomItemVisualKind kind) => _baked[kind];

  bool has(RoomItemVisualKind kind) => _baked.containsKey(kind);

  List<RoomItemVisualKind> missingFrom(Iterable<RoomItemVisualKind> kinds) {
    final missing = <RoomItemVisualKind>[];
    for (final kind in kinds) {
      if (!_baked.containsKey(kind) && !missing.contains(kind)) {
        missing.add(kind);
      }
    }
    return missing;
  }

  void put(RoomItemVisualKind kind, ui.Image image) {
    _baked[kind]?.dispose();
    _baked[kind] = image;
    revision.value += 1;
  }
}

/// A catalog thumbnail: the baked render once it exists, the Kenney sprite until
/// then (and permanently, if the device's GL readback doesn't cooperate).
class FurnitureThumbnail extends StatelessWidget {
  const FurnitureThumbnail({
    super.key,
    required this.definition,
    this.size = 132,
  });

  final RoomItemDefinition definition;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: FurnitureThumbnails.instance.revision,
      builder: (context, _, _) {
        final image = FurnitureThumbnails.instance.imageFor(
          definition.visualKind,
        );
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: image == null
              ? RoomSpriteThumbnail(
                  key: const ValueKey('sprite'),
                  definition: definition,
                  size: size,
                )
              : SizedBox(
                  key: const ValueKey('baked'),
                  width: size,
                  height: size,
                  child: RawImage(
                    image: image,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
        );
      },
    );
  }
}

/// The shop's live turntable. Owns the single renderer, bakes the card
/// thumbnails on the way up, then spins the selected piece.
class FurniturePreviewStage extends StatefulWidget {
  const FurniturePreviewStage({
    super.key,
    required this.definition,
    required this.bakeKinds,
    this.height = 208,
  });

  /// The piece on the turntable, or null to idle on the last one.
  final RoomItemDefinition? definition;

  /// Every kind the catalog can show, baked to thumbnails on first setup.
  final List<RoomItemVisualKind> bakeKinds;

  final double height;

  /// Turn off to keep the stage on its still thumbnails and never open a GL
  /// context. Widget tests set this: under the test binding the platform
  /// channels behind the renderer never answer, so it leaves timers pending at
  /// teardown. Doubles as a kill switch if a device turns out to hate the
  /// turntable.
  static bool rendererEnabled = true;

  @override
  State<FurniturePreviewStage> createState() => _FurniturePreviewStageState();
}

class _FurniturePreviewStageState extends State<FurniturePreviewStage> {
  // Matches the room view's own warm-up: long enough for whoever held the GL
  // claim before us to finish tearing their context down.
  static const Duration _handoffDelay = Duration(milliseconds: 380);
  static const double _stageWidth = 232;
  static const double _stageHeight = 196;
  static const int _bakePixels = 208;
  static const double _spinRadiansPerSecond = 0.55;
  static const double _dragRadiansPerPixel = 0.011;

  final Object _glToken = Object();

  three.ThreeJS? _threeJs;
  three.Group? _pivot;
  three.PerspectiveCamera? _camera;
  Timer? _startTimer;

  /// Setup finished: scene and camera exist and nothing is still running inside
  /// `setup`, which is the point where [three.ThreeJS.dispose] becomes safe to
  /// call. Also what the build method waits on before showing the live texture.
  bool _ready = false;

  /// Teardown was asked for mid-setup; dispose as soon as setup completes.
  bool _disposeWhenReady = false;

  /// Set when that deferred teardown is the last thing standing between us and
  /// giving the context back — i.e. this State is already gone.
  bool _releaseTokenAfterDispose = false;

  /// The turntable sits still until the student actually asks to see a piece —
  /// tapping a catalog card to preview it, tapping the stage, or dragging it.
  /// A preview that spins on its own the moment the shop opens is noise.
  bool _spinning = false;
  bool _spinningBeforeDrag = false;
  double _spinPhase = 0;

  @override
  void initState() {
    super.initState();
    RoomGlGate.claim(_glToken);
    RoomGlGate.activeOwner.addListener(_handleGlOwnerChanged);
    _scheduleStart();
  }

  @override
  void didUpdateWidget(covariant FurniturePreviewStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.definition?.visualKind != oldWidget.definition?.visualKind) {
      _showSelectedKind();
      // Tapping a card to put a piece on the turntable is the ask.
      _spinning = true;
    }
  }

  @override
  void dispose() {
    RoomGlGate.activeOwner.removeListener(_handleGlOwnerChanged);
    _startTimer?.cancel();
    _startTimer = null;

    final threeJs = _threeJs;
    if (threeJs != null && !_ready) {
      // Leaving the shop while the context is still coming up. Disposing now
      // would throw on its half-built scene, and abandoning it would leave a
      // second context alive behind the room view — the exact thing the gate
      // exists to prevent. Hold the claim until setup lands and tears it down.
      _disposeWhenReady = true;
      _releaseTokenAfterDispose = true;
      super.dispose();
      return;
    }

    _threeJs = null;
    threeJs?.dispose();
    RoomGlGate.release(_glToken);
    super.dispose();
  }

  void _handleGlOwnerChanged() {
    if (!mounted) {
      return;
    }
    // Someone above us (the editor, opened from a shop card) took the context.
    if (RoomGlGate.holds(_glToken)) {
      _scheduleStart();
    } else {
      _teardown();
    }
  }

  void _scheduleStart() {
    if (!FurniturePreviewStage.rendererEnabled ||
        _threeJs != null ||
        _startTimer != null ||
        !RoomGlGate.holds(_glToken)) {
      return;
    }

    _startTimer = Timer(_handoffDelay, () {
      _startTimer = null;
      if (!mounted || _threeJs != null || !RoomGlGate.holds(_glToken)) {
        return;
      }

      final threeJs = three.ThreeJS(
        settings: three.Settings(
          antialias: true,
          alpha: true,
          clearColor: 0x000000,
          // Transparent so the piece floats on the card's own tint.
          clearAlpha: 0,
          enableShadowMap: false,
        ),
        size: const Size(_stageWidth, _stageHeight),
        setup: _setupScene,
        onSetupComplete: _handleSetupComplete,
        loadingWidget: const SizedBox.shrink(),
      );

      setState(() {
        _threeJs = threeJs;
      });
    });
  }

  void _teardown() {
    _startTimer?.cancel();
    _startTimer = null;

    final threeJs = _threeJs;
    if (threeJs == null) {
      return;
    }

    if (!_ready) {
      // Setup is still running — its scene may be half-built, and disposing out
      // from under it would leave the wrapper starting a ticker on a dead
      // context. Setup always completes, so hand the job to
      // _handleSetupComplete.
      _disposeWhenReady = true;
      return;
    }

    _threeJs = null;
    _pivot = null;
    _camera = null;
    _ready = false;
    threeJs.dispose();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _setupScene() async {
    final threeJs = _threeJs;
    if (threeJs == null) {
      return;
    }

    final camera = three.PerspectiveCamera(
      34,
      _stageWidth / _stageHeight,
      0.1,
      60,
    );
    threeJs.camera = camera;
    threeJs.scene = three.Scene();
    _camera = camera;

    final scene = threeJs.scene;
    // Warmer and flatter than the room's lighting: a preview has no walls to
    // bounce light, so the key alone would leave the far side black.
    scene.add(three.AmbientLight(0xe8d8c8, 0.62));
    final hemi = three.HemisphereLight(0xf6e6d2, 0x40332c, 0.68);
    hemi.position.setValues(0, 8, 0);
    scene.add(hemi);
    final keyLight = three.DirectionalLight(0xffead0, 1.05);
    keyLight.position.setValues(-2.6, 4.4, 3.6);
    scene.add(keyLight);
    final fillLight = three.DirectionalLight(0xf3bea0, 0.42);
    fillLight.position.setValues(3.2, 1.8, -2.6);
    scene.add(fillLight);

    final pivot = three.Group();
    scene.add(pivot);
    _pivot = pivot;

    await _bakeThumbnails();
    if (_threeJs == null || _disposeWhenReady) {
      // The shop closed, or another screen claimed the context, while we were
      // baking. Leave the turntable unwired — this instance is on its way out.
      return;
    }

    _showSelectedKind();
    threeJs.addAnimationEvent(_animateSpin);
  }

  void _handleSetupComplete() {
    if (_disposeWhenReady) {
      _disposeWhenReady = false;
      final threeJs = _threeJs;
      _threeJs = null;
      _pivot = null;
      _camera = null;
      threeJs?.dispose();
      if (_releaseTokenAfterDispose) {
        _releaseTokenAfterDispose = false;
        RoomGlGate.release(_glToken);
      }
      if (mounted) {
        setState(() {});
        // The editor may have opened and closed again while this instance was
        // mid-setup, in which case the claim is ours once more and nothing else
        // is left to restart the turntable.
        _scheduleStart();
      }
      return;
    }

    _ready = true;
    if (mounted) {
      setState(() {});
    }
  }

  void _animateSpin(double dt) {
    final pivot = _pivot;
    if (pivot == null || !_spinning) {
      return;
    }
    _spinPhase = (_spinPhase + dt * _spinRadiansPerSecond) % (2 * math.pi);
    pivot.rotation.y = _spinPhase;
  }

  void _toggleSpin() {
    _spinning = !_spinning;
  }

  void _handleDragStart(DragStartDetails details) {
    _spinningBeforeDrag = _spinning;
    _spinning = false;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final pivot = _pivot;
    if (pivot == null) {
      return;
    }
    _spinPhase =
        (_spinPhase + details.delta.dx * _dragRadiansPerPixel) % (2 * math.pi);
    pivot.rotation.y = _spinPhase;
  }

  void _handleDragEnd() {
    // Back to however it was before the drag, rather than always spinning.
    _spinning = _spinningBeforeDrag;
  }

  /// Swaps the turntable's piece, disposing the old geometry.
  void _showSelectedKind() {
    final pivot = _pivot;
    final camera = _camera;
    final kind = widget.definition?.visualKind;
    if (pivot == null || camera == null || kind == null) {
      return;
    }

    for (final child in List<three.Object3D>.from(pivot.children)) {
      pivot.remove(child);
      child.dispose();
    }

    final model = buildFurnitureVisual(kind);
    _centerOnOrigin(model);
    pivot.add(model);
    camera.aspect = _stageWidth / _stageHeight;
    _frameCamera(camera, model);
  }

  /// Renders every catalog piece to an offscreen target and reads it back as an
  /// image. Runs inside `setup`, before the ticker starts, so nothing else is
  /// touching the context; the GL work is synchronous and the (slower) decode
  /// happens afterwards.
  Future<void> _bakeThumbnails() async {
    final threeJs = _threeJs;
    final renderer = threeJs?.renderer;
    final texture = threeJs?.texture;
    final camera = _camera;
    final pivot = _pivot;
    if (threeJs == null ||
        renderer == null ||
        texture == null ||
        camera == null ||
        pivot == null) {
      return;
    }

    final pending = FurnitureThumbnails.instance.missingFrom(widget.bakeKinds);
    if (pending.isEmpty) {
      return;
    }

    const size = _bakePixels;
    final target = three.WebGLRenderTarget(
      size,
      size,
      three.WebGLRenderTargetOptions({
        'format': three.RGBAFormat,
        'type': three.UnsignedByteType,
        'minFilter': three.LinearFilter,
        'magFilter': three.LinearFilter,
        'depthBuffer': true,
        'generateMipmaps': false,
      }),
    );
    final buffer = three.Uint8Array(size * size * 4);
    final baked = <RoomItemVisualKind, Uint8List>{};

    try {
      // Same call the wrapper's own render loop makes — without it the context
      // may not be current on this thread.
      threeJs.angle?.activateTexture(texture);
      camera.aspect = 1;

      for (final kind in pending) {
        final model = buildFurnitureVisual(kind);
        _centerOnOrigin(model);
        pivot.add(model);
        pivot.rotation.y = 0;
        _frameCamera(camera, model);

        // No setViewport here: it scales by the device pixel ratio, so asking
        // for 208x208 on a dpr-3 phone set a 624x624 viewport on a 208x208
        // buffer and every thumbnail came out as a 3x-magnified bottom-left
        // crop. setRenderTarget already sizes the viewport to the target.
        renderer.setRenderTarget(target);
        renderer.clear();
        renderer.render(threeJs.scene, camera);
        renderer.readRenderTargetPixels(target, 0, 0, size, size, buffer);

        final pixels = Uint8List.fromList(buffer.toDartList());
        pivot.remove(model);
        model.dispose();

        if (_hasVisiblePixels(pixels)) {
          baked[kind] = _flipVertically(pixels, size);
        }
      }
    } catch (error, stackTrace) {
      // A device that won't read pixels back just keeps the sprite thumbnails.
      debugPrint('Furniture thumbnail bake failed: $error\n$stackTrace');
    } finally {
      renderer.setRenderTarget(null);
      buffer.dispose();
      target.dispose();
    }

    for (final entry in baked.entries) {
      final image = await _decodeRgba(entry.value, size);
      FurnitureThumbnails.instance.put(entry.key, image);
    }
  }

  /// Sits the piece's bounding-box centre on the origin so the turntable spins
  /// around it instead of swinging it in an arc.
  void _centerOnOrigin(three.Object3D model) {
    final bounds = three.BoundingBox().setFromObject(model);
    if (bounds.isEmpty()) {
      return;
    }
    final center = bounds.getCenter(three.Vector3());
    model.position.setValues(-center.x, -center.y, -center.z);
  }

  /// Pulls the camera back far enough for the whole piece to fit, whichever axis
  /// is tightest, and re-aims it at the origin.
  void _frameCamera(three.PerspectiveCamera camera, three.Object3D model) {
    final bounds = three.BoundingBox().setFromObject(model);
    if (bounds.isEmpty()) {
      return;
    }

    final extent = three.Vector3().setFrom(bounds.max).sub(bounds.min);
    final radius =
        0.5 *
        math.sqrt(
          extent.x * extent.x + extent.y * extent.y + extent.z * extent.z,
        );
    if (radius <= 0) {
      return;
    }

    final verticalFov = camera.fov * math.pi / 180;
    final horizontalFov =
        2 * math.atan(math.tan(verticalFov / 2) * camera.aspect);
    final tightestFov = math.min(verticalFov, horizontalFov);
    // 1.22 keeps a little air around the piece so nothing kisses the edge.
    final distance = radius * 1.22 / math.sin(tightestFov / 2);

    final direction = three.Vector3(0.78, 0.56, 1.0).normalize();
    camera.position.setFrom(direction.scale(distance));
    camera.lookAt(three.Vector3.zero());
    camera.near = math.max(0.05, distance - radius * 4);
    camera.far = distance + radius * 8;
    camera.updateProjectionMatrix();
  }

  /// GL hands back rows bottom-up; Flutter wants them top-down.
  Uint8List _flipVertically(Uint8List pixels, int size) {
    final stride = size * 4;
    final flipped = Uint8List(pixels.length);
    for (var row = 0; row < size; row += 1) {
      final source = row * stride;
      final destination = (size - 1 - row) * stride;
      flipped.setRange(destination, destination + stride, pixels, source);
    }
    return flipped;
  }

  /// Guards against caching an empty frame on a device where the readback
  /// silently produced nothing — the sprite fallback is better than a blank card.
  bool _hasVisiblePixels(Uint8List pixels) {
    for (var i = 3; i < pixels.length; i += 4) {
      if (pixels[i] != 0) {
        return true;
      }
    }
    return false;
  }

  Future<ui.Image> _decodeRgba(Uint8List pixels, int size) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      size,
      size,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final threeJs = _threeJs;
    final showLive = threeJs != null && _ready;
    final definition = widget.definition;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleSpin,
        onHorizontalDragStart: _handleDragStart,
        onHorizontalDragUpdate: _handleDragUpdate,
        onHorizontalDragEnd: (_) => _handleDragEnd(),
        onHorizontalDragCancel: _handleDragEnd,
        child: Center(
          child: SizedBox(
            width: _stageWidth,
            height: _stageHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The still thumbnail holds the frame until the context is up,
                // and stands in whenever another screen owns the renderer.
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 240),
                  opacity: showLive ? 0 : 1,
                  child: Center(
                    child: definition == null
                        ? const SizedBox.shrink()
                        : FurnitureThumbnail(
                            definition: definition,
                            size: _stageHeight * 0.86,
                          ),
                  ),
                ),
                if (threeJs != null)
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 240),
                    opacity: showLive ? 1 : 0,
                    child: threeJs.build(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
