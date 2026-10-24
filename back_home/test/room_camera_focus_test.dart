import 'dart:math' as math;

import 'package:back_home/rooms/room_camera_focus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js/three_js.dart' as three;

RoomFocusPose _focus(
  three.Vector3 eye,
  three.Vector3 point, {
  double distance = 2.6,
  double minHeight = 0.7,
}) => roomFocusPoseForPoint(
  eye: eye,
  point: point,
  standDistance: distance,
  maxX: 4.6,
  maxZ: 7.5,
  minEyeHeight: minHeight,
);

void _expectCentered(RoomFocusPose pose, three.Vector3 point) {
  final camera = three.PerspectiveCamera(42, 393 / 852, 0.1, 80);
  camera.position.setFrom(pose.position);
  camera.lookAt(
    pose.position.clone()
      ..add(three.Vector3(math.sin(pose.yaw), pose.pitch, -math.cos(pose.yaw))),
  );
  camera.updateMatrixWorld(true);
  final projected = point.clone()..project(camera);
  expect(projected.x, closeTo(0, 1e-5));
  expect(projected.y, closeTo(0, 1e-5));
}

three.Mesh _box(double w, double h, double d, double x, double y, double z) {
  final box = three.Mesh(three.BoxGeometry(w, h, d), three.MeshBasicMaterial());
  box.position.setValues(x, y, z);
  box.updateMatrixWorld(true);
  addTearDown(box.dispose);
  return box;
}

void main() {
  test(
    'repeated desk focus from an off-centre eye does not orbit or back away',
    () {
      final eye = three.Vector3(-2.2, 1.9, -1.1);
      final point = three.Vector3(1.4, 1.05, -7.4);
      final pose = _focus(eye, point);
      final initialDirection = point.clone()..sub(eye);
      final travelDirection = pose.position.clone()..sub(eye);
      expect(
        travelDirection.x / travelDirection.z,
        closeTo(initialDirection.x / initialDirection.z, 1e-6),
      );
      _expectCentered(pose, point);

      var repeated = pose;
      for (var i = 0; i < 8; i++) {
        repeated = _focus(repeated.position, point);
        expect(repeated.position.distanceTo(pose.position), lessThan(1e-6));
        expect(repeated.yaw, closeTo(pose.yaw, 1e-6));
        expect(repeated.pitch, closeTo(pose.pitch, 1e-6));
      }
      expect(eye.x, closeTo(-2.2, 1e-6));
      expect(point.x, closeTo(1.4, 1e-6));
    },
  );

  test(
    'a desk tap within the stand distance keeps the current camera position',
    () {
      final eye = three.Vector3(0.8, 1.9, -6.8);
      final point = three.Vector3(1.0, 0.9, -7.2);
      final pose = _focus(eye, point);
      expect(pose.position.distanceTo(eye), lessThan(1e-9));
      _expectCentered(pose, point);
    },
  );

  test('window corners each focus the actual touched point', () {
    final eye = three.Vector3(0, 1.9, 0);
    final poses = <RoomFocusPose>[];
    for (final x in [-1.2, 3.2]) {
      for (final y in [1.2, 3.5]) {
        final point = three.Vector3(x, y, -7.72);
        final pose = _focus(eye, point, distance: 1.1);
        _expectCentered(pose, point);
        expect(pose.position.z, greaterThan(-7.5));
        poses.add(pose);
      }
    }
    expect(poses[0].position.x, lessThan(poses[2].position.x));
    expect(poses[0].pitch, lessThan(poses[1].pitch));
  });

  test('bed head and foot keep distinct anchors and stable repeat focus', () {
    final eye = three.Vector3(1.7, 1.9, 0);
    final head = three.Vector3(-0.8, 0.85, -5.8);
    final foot = three.Vector3(-0.4, 0.6, -2.0);
    final headPose = _focus(eye, head, distance: 2, minHeight: 1.7);
    final footPose = _focus(eye, foot, distance: 2, minHeight: 1.7);
    _expectCentered(headPose, head);
    _expectCentered(footPose, foot);
    expect(headPose.position.distanceTo(footPose.position), greaterThan(1));
    final repeated = _focus(
      headPose.position,
      head,
      distance: 2,
      minHeight: 1.7,
    );
    expect(repeated.position.distanceTo(headPose.position), lessThan(1e-6));
  });

  test(
    'lower window glass is not intercepted by the visible desk below it',
    () {
      final window = _box(4.9, 2.7, 0.08, 1, 2.35, -7.72);
      final desktop = _box(5.1, 0.34, 1.1, 1, 0.7, -7.42);
      final eye = three.Vector3(0, 1.9, 0);
      final direction = three.Vector3(0, 1.65, -7.72)
        ..sub(eye)
        ..normalize();
      final ray = three.Raycaster(eye, direction);
      final hit = nearestRoomTapIntersection(
        ray,
        furniture: [],
        surfaces: [desktop, window],
      );
      expect(hit?.object, same(window));
    },
  );

  test('depth ordering is shared by movable furniture and window surfaces', () {
    final window = _box(4.9, 2.7, 0.08, 1, 2.35, -7.72);
    final behind = _box(1, 1, 0.5, 1, 2.3, -9);
    final ray = three.Raycaster(
      three.Vector3(1, 2.3, 0),
      three.Vector3(0, 0, -1),
    );
    expect(
      nearestRoomTapIntersection(
        ray,
        furniture: [behind],
        surfaces: [window],
      )?.object,
      same(window),
    );

    final foreground = _box(1, 1, 0.5, 1, 2.3, -4);
    expect(
      nearestRoomTapIntersection(
        ray,
        furniture: [foreground, behind],
        surfaces: [window],
      )?.object,
      same(foreground),
    );
  });

  test('radio retains its own hit in front of the desk and window', () {
    final desktop = _box(5.1, 0.34, 1.1, 1, 0.7, -7.42);
    final radio = _box(0.92, 0.6, 0.5, 1.52, 1.12, -7.59);
    final window = _box(4.9, 2.7, 0.08, 1, 2.35, -7.72);
    final eye = three.Vector3(0, 1.9, 0);
    final direction = radio.position.clone()
      ..sub(eye)
      ..normalize();
    final ray = three.Raycaster(eye, direction);
    expect(
      nearestRoomTapIntersection(
        ray,
        furniture: [],
        surfaces: [desktop, window, radio],
      )?.object,
      same(radio),
    );
  });
}
