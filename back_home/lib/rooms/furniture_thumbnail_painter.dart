import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

import 'furniture_models.dart';
import 'room_state.dart';

/// Projects the actual room mesh, including each recipe's shape and finish.
/// A bounded picture cache avoids hundreds of GL contexts or an eager bake of
/// the entire catalog. The live detail preview still uses the room's renderer.
class FurnitureMeshThumbnail extends StatelessWidget {
  const FurnitureMeshThumbnail({
    super.key,
    required this.definition,
    this.size = 132,
  });
  final RoomItemDefinition definition;
  final double size;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MeshPainter(definition)),
    ),
  );
}

class _Face {
  _Face(this.points, this.depth, this.color);
  final List<Offset> points;
  final double depth;
  final Color color;
}

class _Triangle {
  _Triangle(this.points, this.depths, this.color);
  final List<Offset> points;
  final List<double> depths;
  final Color color;

  void split(double cell, List<_Face> out) {
    final a = points[0], b = points[1], c = points[2];
    final area = (b - a).dx * (c - a).dy - (b - a).dy * (c - a).dx;
    if (area.abs() < 1e-9) return;
    double depthAt(Offset p) {
      final u = ((b - p).dx * (c - p).dy - (b - p).dy * (c - p).dx) / area;
      final v = ((c - p).dx * (a - p).dy - (c - p).dy * (a - p).dx) / area;
      final depth = u * depths[0] + v * depths[1] + (1 - u - v) * depths[2];
      return depth;
    }

    final x0 = (points.map((p) => p.dx).reduce(math.min) / cell).floor();
    final x1 = (points.map((p) => p.dx).reduce(math.max) / cell).floor();
    final y0 = (points.map((p) => p.dy).reduce(math.min) / cell).floor();
    final y1 = (points.map((p) => p.dy).reduce(math.max) / cell).floor();
    for (var i = x0; i <= x1; i++) {
      for (var j = y0; j <= y1; j++) {
        final left = i * cell, top = j * cell;
        var polygon = points;
        polygon = _clip(polygon, (p) => p.dx - left);
        polygon = _clip(polygon, (p) => left + cell - p.dx);
        polygon = _clip(polygon, (p) => p.dy - top);
        polygon = _clip(polygon, (p) => top + cell - p.dy);
        if (polygon.length < 3) continue;
        var centre = Offset.zero;
        for (final p in polygon) {
          centre += p;
        }
        out.add(
          _Face(polygon, depthAt(centre / polygon.length.toDouble()), color),
        );
      }
    }
  }

  /// Sutherland–Hodgman against one grid line; [inside] is >= 0 inside.
  static List<Offset> _clip(
    List<Offset> polygon,
    double Function(Offset) inside,
  ) {
    final result = <Offset>[];
    for (var k = 0; k < polygon.length; k++) {
      final p = polygon[k], q = polygon[(k + 1) % polygon.length];
      final dp = inside(p), dq = inside(q);
      if (dp >= 0) result.add(p);
      if ((dp >= 0) != (dq >= 0)) {
        result.add(Offset.lerp(p, q, dp / (dp - dq))!);
      }
    }
    return result;
  }
}

class _MeshPainter extends CustomPainter {
  _MeshPainter(this.definition);
  final RoomItemDefinition definition;
  static final _cache = <String, ui.Picture>{};
  static const _pixels = 256.0;

  ui.Picture _picture() {
    final cached = _cache.remove(definition.id);
    if (cached != null) {
      _cache[definition.id] = cached;
      return cached;
    }
    final model = buildFurnitureVisualFor(definition);
    model.updateMatrixWorld(true);
    final forward = three.Vector3(.78, .56, 1).normalize();
    final right = three.Vector3(forward.z, 0, -forward.x).normalize();
    final up = three.Vector3().cross2(forward, right).normalize();
    Offset project(three.Vector3 v) => Offset(v.dot(right), -v.dot(up));
    final triangles = <_Triangle>[];
    final faces = <_Face>[];
    void visit(three.Object3D object) {
      if (object is three.Mesh) {
        final geometry = object.geometry;
        final positions = geometry?.getAttributeFromString('position');
        final indices = geometry?.index;
        final material = object.material;
        if (positions != null && material is three.Material) {
          final base = material.color;
          final count = (indices?.count ?? positions.count) as int;
          three.Vector3 vertex(int i) {
            final index = indices == null ? i : indices.getX(i)!.toInt();
            return three.Vector3(
              positions.getX(index).toDouble(),
              positions.getY(index).toDouble(),
              positions.getZ(index).toDouble(),
            )..applyMatrix4(object.matrixWorld);
          }

          for (var i = 0; i + 2 < count; i += 3) {
            final a = vertex(i), b = vertex(i + 1), c = vertex(i + 2);
            final normal = three.Vector3()
                .cross2(three.Vector3().sub2(b, a), three.Vector3().sub2(c, a))
                .normalize();
            if (normal.dot(forward) <= .001) continue;
            final light =
                (.68 +
                        .32 *
                            normal.dot(three.Vector3(-.4, .85, .6).normalize()))
                    .clamp(.4, 1.0);
            final color = Color.fromARGB(
              255,
              (base.red * 255 * light).round().clamp(0, 255),
              (base.green * 255 * light).round().clamp(0, 255),
              (base.blue * 255 * light).round().clamp(0, 255),
            );
            triangles.add(
              _Triangle(
                [project(a), project(b), project(c)],
                [a.dot(forward), b.dot(forward), c.dot(forward)],
                color,
              ),
            );
          }
        }
      }
      for (final child in object.children) {
        visit(child);
      }
    }

    visit(model);
    model.dispose();
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final triangle in triangles) {
      for (final p in triangle.points) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
    }
    // A painter's sort by whole-triangle centroid lets a long face (a shelf,
    // a sofa base) paint over the smaller parts in front of it. Instead every
    // triangle is cut along a screen grid and each piece is ordered by its
    // own centroid: faces that both fill a cell are compared at the same
    // point, and pieces in different cells never overlap.
    final cell = math.max(maxX - minX, maxY - minY) / 32;
    for (final triangle in triangles) {
      triangle.split(cell, faces);
    }
    faces.sort((a, b) => a.depth.compareTo(b.depth));
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (faces.isNotEmpty) {
      final scale = 222 / math.max(maxX - minX, maxY - minY);
      canvas.translate(128, 126);
      canvas.scale(scale);
      canvas.translate(-(minX + maxX) / 2, -(minY + maxY) / 2);
      final paint = Paint()..isAntiAlias = false;
      for (final face in faces) {
        final path = Path()..addPolygon(face.points, true);
        paint.color = face.color;
        canvas.drawPath(path, paint);
      }
    }
    final picture = recorder.endRecording();
    _cache[definition.id] = picture;
    while (_cache.length > 64) {
      _cache.remove(_cache.keys.first)?.dispose();
    }
    return picture;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _pixels, size.height / _pixels);
    canvas.drawPicture(_picture());
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) =>
      oldDelegate.definition.id != definition.id;
}
