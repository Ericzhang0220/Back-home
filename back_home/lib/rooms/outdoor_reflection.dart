part of 'outdoor_landscape.dart';

/// A real mirror image of the scenery for a flat water surface: the scene drawn
/// again from the camera's reflection under the water, into a texture the water
/// shader looks up. It follows the camera, so it stays sharp at any zoom.
///
/// It only redraws while the camera moves, and now and then to pick up drifting
/// clouds. Anything that moves quickly is left out rather than stuttering.
class _PlanarReflection {
  _PlanarReflection({required this.level});

  final double level;

  static const int _width = 768;
  static const int _height = 1536;
  // Wider than the real view, so ripples have something to pull in at the edge.
  static const double _margin = 1.2;
  static const double _refreshSeconds = 0.5;

  final three.PerspectiveCamera _mirror = three.PerspectiveCamera(
    60,
    1,
    0.1,
    240,
  );
  final three.Vector3 _target = three.Vector3();
  three.WebGLRenderTarget? _renderTarget;

  /// World position to clip space of the mirror camera, for the water shader.
  final three.Matrix4 matrix = three.Matrix4.identity();

  /// Placeholder until the first draw, then the mirrored scene.
  final three.Texture blank =
      three.DataTexture(
          three.Uint8Array.fromList(const [8, 12, 20, 255]),
          1,
          1,
          three.RGBAFormat,
          three.UnsignedByteType,
        )
        ..magFilter = three.LinearFilter
        ..minFilter = three.LinearFilter
        ..needsUpdate = true;

  double _sinceDraw = double.infinity;
  final List<double> _lastPose = List<double>.filled(17, double.nan);

  /// Redraws if needed. Returns the texture to sample once one has been drawn.
  three.Texture? update(
    double dt,
    three.WebGLRenderer renderer,
    three.Scene scene,
    three.PerspectiveCamera camera,
    List<three.Object3D> outdoors,
    List<three.Object3D> hidden,
  ) {
    _sinceDraw += dt;
    camera.updateMatrixWorld();
    final world = camera.matrixWorld.storage;
    // Facing back into the room: no water in view, so nothing to keep fresh.
    if (world[10] < -0.2 && _renderTarget != null) {
      return _renderTarget!.texture;
    }
    var moved = camera.fov != _lastPose[16];
    for (var i = 0; i < 16 && !moved; i += 1) {
      moved = (world[i] - _lastPose[i]).abs() > 1e-5;
    }
    if (!moved && _sinceDraw < _refreshSeconds && _renderTarget != null) {
      return _renderTarget!.texture;
    }
    for (var i = 0; i < 16; i += 1) {
      _lastPose[i] = world[i];
    }
    _lastPose[16] = camera.fov;
    _sinceDraw = 0;
    _aim(camera);
    return _draw(renderer, scene, outdoors, hidden);
  }

  void _aim(three.PerspectiveCamera camera) {
    final m = camera.matrixWorld.storage;
    final mirrorY = 2 * level - m[13];
    _mirror
      ..position.setValues(m[12], mirrorY, m[14])
      ..up.setValues(m[4], -m[5], m[6])
      ..aspect = camera.aspect
      ..near = camera.near
      ..far = 240
      ..fov =
          2 *
          math.atan(math.tan(camera.fov * math.pi / 360) * _margin) *
          180 /
          math.pi;
    _target.setValues(m[12] - m[8], mirrorY + m[9], m[14] - m[10]);
    _mirror
      ..lookAt(_target)
      ..updateProjectionMatrix()
      ..updateMatrixWorld(true);
    _clipAtWater();
    matrix
      ..setFrom(_mirror.projectionMatrix)
      ..multiply(_mirror.matrixWorldInverse);
  }

  /// Bends the near plane onto the water (Lengyel's oblique clipping), so that
  /// whatever is under the surface, including the bank between the mirror
  /// camera and the river, can't block the view.
  void _clipAtWater() {
    final view = _mirror.matrixWorldInverse.storage;
    final proj = _mirror.projectionMatrix.storage;
    // The plane y = level, in view space.
    final nx = view[4];
    final ny = view[5];
    final nz = view[6];
    // A point on the plane in view space is view * (0, level, 0).
    final px = view[4] * level + view[12];
    final py = view[5] * level + view[13];
    final pz = view[6] * level + view[14];
    final w = -(nx * px + ny * py + nz * pz);
    final qx = (nx.sign + proj[8]) / proj[0];
    final qy = (ny.sign + proj[9]) / proj[5];
    const qz = -1.0;
    final qw = (1 + proj[10]) / proj[14];
    final scale = 2 / (nx * qx + ny * qy + nz * qz + w * qw);
    proj[2] = nx * scale;
    proj[6] = ny * scale;
    proj[10] = nz * scale + 1 - 0.0005;
    proj[14] = w * scale;
    _mirror.projectionMatrixInverse
      ..setFrom(_mirror.projectionMatrix)
      ..invert();
  }

  three.Texture _draw(
    three.WebGLRenderer renderer,
    three.Scene scene,
    List<three.Object3D> outdoors,
    List<three.Object3D> hidden,
  ) {
    var target = _renderTarget;
    final fresh = target == null;
    target ??= three.WebGLRenderTarget(
      _width,
      _height,
      three.WebGLRenderTargetOptions({
        'format': three.RGBAFormat,
        'type': three.UnsignedByteType,
        'magFilter': three.LinearFilter,
        'minFilter': three.LinearMipmapLinearFilter,
        'wrapS': three.ClampToEdgeWrapping,
        'wrapT': three.ClampToEdgeWrapping,
        'generateMipmaps': true,
        'depthBuffer': true,
      }),
    );
    _renderTarget = target;
    // Treated like the screen, so materials keep the same shader program and
    // colours as the main pass (see the set of texture.colorSpace below).
    target.isXRRenderTarget = true;

    final restore = <three.Object3D>[];
    for (final child in scene.children) {
      if (child.visible && child is! three.Light && !outdoors.contains(child)) {
        child.visible = false;
        restore.add(child);
      }
    }
    for (final object in hidden) {
      if (object.visible) {
        object.visible = false;
        restore.add(object);
      }
    }
    final autoShadows = renderer.shadowMap.autoUpdate;
    renderer.shadowMap.autoUpdate = false;
    renderer.setRenderTarget(target);
    if (fresh) {
      // Only after the first bind allocated plain RGBA8: set any earlier and
      // the texture would be an sRGB one the GPU converts on its own.
      target.texture.colorSpace = renderer.outputColorSpace;
    }
    renderer.clear();
    renderer.render(scene, _mirror);
    renderer.setRenderTarget(null);
    renderer.shadowMap.autoUpdate = autoShadows;
    for (final object in restore) {
      object.visible = true;
    }
    return target.texture;
  }

  void dispose() {
    _renderTarget?.dispose();
    blank.dispose();
  }
}
