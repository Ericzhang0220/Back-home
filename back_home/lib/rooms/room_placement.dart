import 'dart:math' as math;

import 'package:three_js/three_js.dart' as three;

import 'furniture_models.dart';
import 'room_state.dart';

typedef RoomViewPose = ({double x, double y, double z, double yaw, double pitch});

const RoomViewPose defaultRoomViewPose = (x: 0, y: 1.9, z: 0, yaw: 0, pitch: -.22);

/// Local model bounds from the same geometry that the room renders.
final _modelBounds = <RoomItemDefinition, ({double x, double z, double bottom, double top, double halfWidth, double halfDepth})>{};

RoomPlacementBox roomPlacementBox(RoomItemDefinition definition, GridPoint origin, double degrees, double elevation) {
  final bounds = _modelBounds.putIfAbsent(definition, () {
    final model = buildFurnitureVisualFor(definition);
    final box = three.BoundingBox().setFromObject(model);
    final result = (
      x: (box.max.x + box.min.x) / 2,
      z: (box.max.z + box.min.z) / 2,
      bottom: box.min.y,
      top: box.max.y,
      halfWidth: (box.max.x - box.min.x) / 2,
      halfDepth: (box.max.z - box.min.z) / 2,
    );
    model.dispose();
    return result;
  });
  final angle = degrees * math.pi / 180;
  final cos = math.cos(angle);
  final sin = math.sin(angle);
  return RoomPlacementBox(
    x: origin.x + definition.width / 2 + bounds.x * cos + bounds.z * sin,
    z: origin.z + definition.depth / 2 - bounds.x * sin + bounds.z * cos,
    bottom: elevation + bounds.bottom,
    top: elevation + bounds.top,
    halfWidth: bounds.halfWidth,
    halfDepth: bounds.halfDepth,
    heading: angle,
  );
}

class RoomPlacementBox {
  const RoomPlacementBox({
    required this.x, required this.z, required this.bottom, required this.top,
    required this.halfWidth, required this.halfDepth, required this.heading,
  });
  final double x, z, bottom, top, halfWidth, halfDepth, heading;
  double get extentX => _extent(1, 0);
  double get extentZ => _extent(0, 1);

  double _extent(double axisX, double axisZ) {
    final cos = math.cos(heading);
    final sin = math.sin(heading);
    return halfWidth * (axisX * cos - axisZ * sin).abs() +
        halfDepth * (axisX * sin + axisZ * cos).abs();
  }

  bool overlaps(RoomPlacementBox other) {
    const tolerance = .001;
    if (top <= other.bottom + tolerance || bottom >= other.top - tolerance) return false;
    for (final angle in [heading, heading + math.pi / 2, other.heading, other.heading + math.pi / 2]) {
      final axisX = math.cos(angle);
      final axisZ = -math.sin(angle);
      final distance = ((x - other.x) * axisX + (z - other.z) * axisZ).abs();
      if (distance >= _extent(axisX, axisZ) + other._extent(axisX, axisZ) - tolerance) return false;
    }
    return true;
  }

  bool blocksEye(double worldX, double y, double worldZ, double clearance) {
    if (y + clearance <= bottom || y - clearance >= top) return false;
    final dx = worldX + RoomEditorController.roomWidth / 2 - x;
    final dz = worldZ + RoomEditorController.roomDepth / 2 - z;
    final cos = math.cos(heading);
    final sin = math.sin(heading);
    return (dx * cos - dz * sin).abs() < halfWidth + clearance &&
        (dx * sin + dz * cos).abs() < halfDepth + clearance;
  }
}
