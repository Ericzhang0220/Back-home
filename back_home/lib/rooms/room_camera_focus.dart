import 'dart:math' as math;

import 'package:three_js/three_js.dart' as three;

typedef RoomFocusPose = ({three.Vector3 position, double yaw, double pitch});

/// Approaches the touched point from the current side, keeping a stable height.
/// A second focus never backs away or orbits around the room's origin.
RoomFocusPose roomFocusPoseForPoint({
  required three.Vector3 eye,
  required three.Vector3 point,
  required double standDistance,
  required double maxX,
  required double maxZ,
  double minEyeHeight = 0.7,
}) {
  final direction = point.clone()..sub(eye);
  final distance = math.sqrt(
    direction.x * direction.x + direction.z * direction.z,
  );
  final travel = math.max(0.0, distance - standDistance);
  final position = eye.clone();
  if (distance > 1e-6) {
    position.x += direction.x * travel / distance;
    position.z += direction.z * travel / distance;
  }
  position.setValues(
    position.x.clamp(-maxX, maxX).toDouble(),
    position.y.clamp(minEyeHeight, 4.6).toDouble(),
    position.z.clamp(-maxZ, maxZ).toDouble(),
  );
  final aim = point.clone()..sub(position);
  final horizontal = math.sqrt(aim.x * aim.x + aim.z * aim.z);
  return (
    position: position,
    yaw: math.atan2(aim.x, -aim.z),
    pitch: aim.y / math.max(horizontal, 1e-6),
  );
}

/// Furniture and built-in surfaces share one depth ordering. Furniture behind
/// a window must not win simply because it belongs to a different collection.
three.Intersection? nearestRoomTapIntersection(
  three.Raycaster raycaster, {
  required List<three.Object3D> furniture,
  required List<three.Object3D> surfaces,
}) {
  final hits = raycaster.intersectObjects([...furniture, ...surfaces], true);
  return hits.isEmpty ? null : hits.first;
}
