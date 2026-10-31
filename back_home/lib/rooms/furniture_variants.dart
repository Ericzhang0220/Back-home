part of 'furniture_models.dart';

FurniturePalette _studioPalette(RoomItemVisualKind kind, int finish) {
  final p = switch (finish) {
    0 => const FurniturePalette(
      frame: Color(0xFFB78C59),
      surface: Color(0xFFD9B785),
      accent: Color(0xFFEAD5B5),
      hardware: Color(0xFF66503A),
      soft: Color(0xFFD6C8AF),
    ),
    1 => const FurniturePalette(
      frame: Color(0xFF654637),
      surface: Color(0xFF8E6750),
      accent: Color(0xFFB59870),
      hardware: Color(0xFF303332),
      soft: Color(0xFFAA7659),
    ),
    _ => const FurniturePalette(
      frame: Color(0xFFE4DFD3),
      surface: Color(0xFFF4F0E6),
      accent: Color(0xFFBC9955),
      hardware: Color(0xFF977844),
      soft: Color(0xFFE7E0CC),
    ),
  };
  if (kind == RoomItemVisualKind.floorLamp) {
    if (finish == 1) {
      return p.copyWith(
        frame: const Color(0xFF303332),
        surface: const Color(0xFF3D4140),
        accent: const Color(0xFF4F514B),
        soft: const Color(0xFF77786B),
      );
    }
    if (finish == 2) {
      return p.copyWith(
        frame: const Color(0xFFBC9955),
        accent: const Color(0xFFF1E8D7),
        soft: const Color(0xFFD8CBB3),
      );
    }
  }
  if (kind == RoomItemVisualKind.plant) {
    return p.copyWith(
      soft: const Color(0xFF678365),
      hardware: const Color(0xFF52634A),
      surface: const Color(0xFF4C3A2B),
      frame: [
        const Color(0xFFB67754),
        const Color(0xFFE1D8C7),
        const Color(0xFFA8AA9B),
      ][finish],
    );
  }
  return p;
}

/// Low-poly joinery, upholstery and turned parts, matching the original room.
/// Form controls geometry; finish also adds grain, stone veins or cane panels.
class _StudioBuilder {
  _StudioBuilder(this.c, this.finish);
  final FurniturePalette c;
  final int finish;
  final three.Group group = three.Group();
  void box(
    double w,
    double h,
    double d,
    double x,
    double y,
    double z,
    Color color, {
    double tilt = 0,
  }) {
    final mesh = furnitureBox(
      width: w,
      height: h,
      depth: d,
      color: color,
      x: x,
      y: y,
      z: z,
    );
    mesh.rotation.z = tilt;
    group.add(mesh);
  }

  void cyl(
    double r,
    double h,
    double x,
    double y,
    double z,
    Color color, {
    double? bottom,
    int sides = 20,
    double tilt = 0,
  }) {
    group.add(
      furnitureCylinder(
        radiusTop: r,
        radiusBottom: bottom ?? r,
        height: h,
        color: color,
        x: x,
        y: y,
        z: z,
        segments: sides,
        tiltZ: tilt,
      ),
    );
  }

  void blob(
    double w,
    double h,
    double d,
    double x,
    double y,
    double z,
    Color color,
  ) {
    group.add(
      furnitureBlob(
        radius: .5,
        color: color,
        scaleX: w,
        scaleY: h,
        scaleZ: d,
        x: x,
        y: y,
        z: z,
      ),
    );
  }

  void cushion(
    double w,
    double h,
    double d,
    double x,
    double y,
    double z,
    Color color,
  ) {
    final geometry = three.SphereGeometry(1, 20, 14);
    final positions = geometry.getAttributeFromString('position');
    double rounded(num v, double extent) =>
        v.sign * math.pow(v.abs(), .3) * extent / 2;
    for (var i = 0; i < positions.count; i++) {
      positions.setXYZ(
        i,
        rounded(positions.getX(i), w),
        rounded(positions.getY(i), h),
        rounded(positions.getZ(i), d),
      );
    }
    geometry.computeVertexNormals();
    group.add(
      three.Mesh(geometry, _material(color))
        ..position.setValues(x, y, z)
        ..castShadow = true
        ..receiveShadow = true,
    );
  }

  void rod(three.Vector3 a, three.Vector3 end, double radius, Color color) {
    final direction = three.Vector3().sub2(end, a);
    final mesh = furnitureCylinder(
      radiusTop: radius,
      radiusBottom: radius,
      height: direction.length,
      color: color,
    );
    mesh.position.setFrom(a).add(end).scale(.5);
    mesh.quaternion.setFromUnitVectors(
      three.Vector3(0, 1, 0),
      direction.normalize(),
    );
    group.add(mesh);
  }

  void legs(
    double w,
    double d,
    double h, {
    double y = 0,
    double x = 0,
    double z = 0,
  }) {
    for (final sx in [-1, 1]) {
      for (final sz in [-1, 1]) {
        cyl(
          .045,
          h,
          x + sx * (w / 2 - .09),
          y + h / 2,
          z + sz * (d / 2 - .09),
          c.hardware,
          bottom: .032,
          sides: 10,
        );
      }
    }
  }

  void top(
    double w,
    double d,
    double y, {
    bool round = false,
    int sides = 28,
    double x = 0,
    double z = 0,
  }) {
    if (round) {
      final mesh = furnitureCylinder(
        radiusTop: .5,
        radiusBottom: .5,
        height: .1,
        color: c.surface,
        x: x,
        y: y,
        z: z,
        segments: sides,
      );
      mesh.scale.setValues(w, 1, d);
      group.add(mesh);
    } else {
      box(w, .1, d, x, y, z, c.surface);
    }
    // Stylised actual joinery/grain or irregular marble veins on the top face.
    for (var i = -2; i <= 2; i++) {
      final offset = i * d * .14;
      final length = round
          ? w * math.sqrt(1 - math.pow(offset / (d * .5), 2)) * .82
          : w * .92;
      final line = furnitureBox(
        width: length,
        height: .003,
        depth: finish == 2 ? .013 : .006,
        color: furnitureShade(c.surface, finish == 2 ? -.2 : -.12),
        x: x,
        y: y + .052,
        z: z + offset,
      );
      if (finish == 2) {
        line.rotation.y = i.isEven ? .08 : -.08;
      }
      group.add(line);
    }
  }

  void drawer(double w, double h, double x, double y, double z) {
    box(w, h, .045, x, y, z, c.surface);
    box(w * .24, .027, .05, x, y, z + .04, c.hardware);
  }

  void cane(double w, double h, double x, double y, double z) {
    for (var i = 0; i < 9; i++) {
      box(.012, h, .012, x - w / 2 + w * i / 8, y, z, c.accent);
    }
    for (var i = 0; i < 8; i++) {
      box(w, .012, .014, x, y - h / 2 + h * i / 7, z, c.accent);
    }
  }
}

three.Group _buildStudioFurniture(
  RoomItemVisualKind kind,
  FurnitureDesign design,
  FurniturePalette c,
) {
  final b = _StudioBuilder(c, design.finish);
  final f = design.form;
  switch (kind) {
    case RoomItemVisualKind.table:
      final w = [1.65, 1.7, 2.75, 2.65, 1.8, 1.45, 1.35, 2.6, 1.9, 1.35][f];
      final d = f == 7
          ? .72
          : (f == 2 || f == 3 ? 1.2 : w.clamp(1.0, 1.8).toDouble());
      final h = f == 5 || f == 6 ? .48 : .85;
      if (f == 6) {
        b.top(1.2, .8, .52, x: -.25, z: -.2, round: true);
        b.legs(.88, .58, .47, x: -.25, z: -.2);
        b.top(.8, .7, .37, x: .45, z: .35, round: true);
        b.legs(.58, .52, .32, x: .45, z: .35);
      } else {
        b.top(w, d, h, round: [1, 3, 5, 9].contains(f), sides: f == 9 ? 8 : 28);
        if (f == 1 || f == 5 || f == 9) {
          b.cyl(.12, h - .1, 0, h / 2, 0, c.frame, bottom: .23);
          b.cyl(w * .3, .07, 0, .035, 0, c.hardware);
        } else if (f == 2 || f == 8) {
          for (final x in [-w * .32, w * .32]) {
            if (f == 8) {
              b.box(.09, .95, .09, x, .43, 0, c.hardware, tilt: .55);
              b.box(.09, .95, .09, x, .43, 0, c.hardware, tilt: -.55);
            } else {
              b.box(.16, h - .1, .72, x, (h - .1) / 2, 0, c.frame);
              b.box(.32, .08, d * .85, x, .04, 0, c.hardware);
            }
          }
          b.box(w * .7, .09, .09, 0, .25, 0, c.frame);
        } else {
          b.legs(f == 3 ? w * .7 : w, f == 3 ? d * .7 : d, h - .05);
        }
        if (f == 4) {
          for (final x in [-.42, .42]) {
            b.box(.012, .006, d * .94, x, h + .055, 0, c.hardware);
          }
          b.box(.7, .07, d * .85, 0, .27, 0, c.frame);
        }
      }
    case RoomItemVisualKind.bed:
      const w = 2.55, d = 3.45;
      b.legs(w, d, .22);
      b.box(w, .24, d, 0, .3, 0, c.frame);
      b.box(w - .16, .22, d - .12, 0, .53, 0, c.accent);
      b.box(w - .18, .19, 2.4, 0, .73, .35, c.soft);
      for (final x in [-.58, .58]) {
        b.blob(1.0, .22, .6, x, .76, -1.12, c.accent);
      }
      if (f == 1 || f == 9) {
        for (var i = 0; i < (f == 1 ? 9 : 5); i++) {
          b.box(
            f == 1 ? .055 : .35,
            .85,
            .09,
            -1.12 + i * (f == 1 ? .28 : .56),
            .9,
            -1.64,
            c.frame,
          );
        }
        b.box(w, .1, .12, 0, 1.33, -1.64, c.frame);
      } else {
        b.box(
          w,
          f == 7 ? 1.2 : .8,
          .14,
          0,
          1,
          -1.64,
          f == 7 ? c.soft : c.surface,
        );
      }
      if (f == 2 || f == 8) {
        for (final x in [-1.2, 1.2]) {
          for (final z in [-1.62, 1.62]) {
            b.cyl(.045, 2.65, x, 1.325, z, c.frame);
          }
          if (f == 8) {
            b.box(.07, .07, d, x, 2.65, 0, c.frame);
          }
        }
        if (f == 8) {
          for (final z in [-1.62, 1.62]) {
            b.box(w, .07, .07, 0, 2.65, z, c.frame);
          }
        }
      }
      if (f == 3) {
        for (final x in [-.65, .65]) {
          b.drawer(1.15, .23, x, .29, 1.74);
        }
      }
      if (f == 4) {
        b.box(.12, .75, d, -1.22, .95, 0, c.surface);
      }
      if (f == 5) {
        for (final x in [-1.22, 1.22]) {
          for (final z in [-1.6, 1.6]) {
            b.box(.09, 2.55, .09, x, 1.275, z, c.frame);
          }
        }
        b.box(w, .18, d, 0, 1.85, 0, c.frame);
        b.box(w - .12, .18, d - .12, 0, 2.03, 0, c.soft);
        b.box(w, .08, .08, 0, 2.4, 1.62, c.frame);
        for (var i = 0; i < 5; i++) {
          b.box(.55, .06, .08, .72, .35 + i * .38, 1.74, c.hardware);
        }
        for (final x in [.42, 1.02]) {
          b.box(.05, 2.2, .06, x, 1.1, 1.74, c.hardware);
        }
      }
      if (f == 6) {
        b.box(w, .8, .18, 0, .72, 1.65, c.frame);
        for (final z in [-1.68, 1.68]) {
          final roll = furnitureCylinder(
            radiusTop: .12,
            radiusBottom: .12,
            height: w,
            color: c.accent,
            y: 1.16,
            z: z,
          );
          roll.rotation.z = math.pi / 2;
          b.group.add(roll);
        }
      }
      if (f == 7) {
        for (final x in [-1.2, 1.2]) {
          b.box(.16, 1.2, .45, x, 1, -1.5, c.soft);
        }
      }
    case RoomItemVisualKind.nightstand:
      if ([2, 7, 8, 9].contains(f)) {
        final round = f == 2 || f == 9;
        b.top(.82, .78, .72, round: round);
        if (f == 8) {
          b.box(.07, .7, .7, -.36, .35, 0, c.hardware);
          b.box(.82, .05, .78, 0, .025, 0, c.hardware);
        } else {
          b.legs(.78, .72, .67);
          b.top(.72, .68, f == 9 ? .32 : .18, round: round);
        }
        if (f == 7) {
          for (final x in [-.39, .39]) {
            b.box(.035, .08, .78, x, .78, 0, c.accent);
          }
        }
      } else {
        b.legs(.78, .72, .16);
        b.box(.78, .54, .72, 0, .43, 0, c.frame);
        b.top(.86, .8, .73);
        if (f == 1) {
          b.box(.65, .27, .025, 0, .48, .37, furnitureShade(c.frame, -.5));
          b.box(.68, .04, .15, 0, .32, .32, c.accent);
        } else if (f == 0 || f == 3) {
          final n = f == 0 ? 1 : 3;
          for (var i = 0; i < n; i++) {
            b.drawer(.69, .45 / n - .02, 0, .23 + (i + .5) * .45 / n, .38);
          }
        } else {
          b.drawer(.68, .44, 0, .44, .38);
          if (f == 5 || design.finish == 1) {
            b.cane(.56, .34, 0, .44, .42);
          }
          if (f == 6) {
            for (var i = 0; i < 13; i++) {
              b.cyl(.013, .43, -.3 + i * .05, .44, .425, c.accent, sides: 8);
            }
          }
        }
      }
    case RoomItemVisualKind.wardrobe:
      const w = 2.5, h = 2.65;
      b.box(w, .12, .82, 0, .06, 0, c.hardware);
      for (final x in [-1.2, 1.2]) {
        b.box(.1, h - .12, .78, x, 1.385, 0, c.frame);
      }
      b.box(w, .09, .8, 0, h, 0, c.frame);
      b.box(w, h - .15, .05, 0, h / 2, -.36, furnitureShade(c.frame, -.1));
      if (f == 4) {
        b.box(w - .2, .04, .04, 0, 2.3, 0, c.hardware);
        for (var i = 0; i < 5; i++) {
          b.box(
            .12,
            .84,
            .35,
            -.75 + i * .38,
            1.75,
            0,
            i.isEven ? c.soft : c.accent,
          );
        }
        b.box(w - .2, .06, .7, 0, .5, 0, c.surface);
      } else {
        final n = f == 1 ? 3 : 2;
        final doorW = f == 9 ? .78 : (w - .16) / n;
        for (var i = 0; i < n; i++) {
          final x = -1.17 + doorW * (i + .5);
          final doorH = f == 5 ? 1.75 : 2.38;
          final y = f == 5 ? 1.69 : 1.35;
          b.box(
            doorW - .035,
            doorH,
            .045,
            x,
            y,
            .41 + (f == 2 ? i * .04 : 0),
            c.surface,
          );
          if (f == 3) {
            b.box(doorW - .15, doorH - .2, .025, x, y, .445, c.glass);
          }
          if (f == 6) {
            for (var j = 0; j < 17; j++) {
              b.box(doorW - .13, .045, .03, x, .26 + j * .13, .45, c.accent);
            }
          }
          if (f == 8 || design.finish == 1) {
            b.cane(doorW - .18, doorH - .25, x, y, .45);
          }
          b.box(.04, .28, .06, x + doorW * .32, y, .48, c.hardware);
        }
        if (f == 5) {
          for (var i = 0; i < 3; i++) {
            b.drawer(2.3, .19, 0, .25 + i * .22, .43);
          }
        }
        if (f == 9) {
          for (var i = 0; i < 5; i++) {
            b.box(.72, .045, .75, .85, .2 + i * .55, 0, c.surface);
          }
        }
        if (f == 7) {
          b.blob(2.45, .65, .78, 0, 2.58, 0, c.frame);
        }
      }
    case RoomItemVisualKind.vanity:
      final h = f == 5 ? 1.15 : .82;
      b.top(2.6, .82, h);
      if (f == 2 || f == 4 || f == 7) {
        for (final x in [-.96, .96]) {
          b.box(.55, h - .08, .7, x, (h - .08) / 2, 0, c.frame);
          for (var i = 0; i < 3; i++) {
            b.drawer(.48, .18, x, .18 + i * .21, .38);
          }
        }
      } else if (f == 6) {
        for (final x in [-.95, .95]) {
          b.box(.09, .83, .08, x, .4, 0, c.frame, tilt: .22);
          b.box(.3, .06, .7, x, .03, 0, c.hardware);
        }
      } else {
        b.legs(2.6, .8, h - .05);
      }
      if (f == 3 || f == 9) {
        b.top(.8, 1.6, h, x: -.9, z: .5);
        b.legs(.8, 1.6, h - .05, x: -.9, z: .5);
      }
      if (f == 1 || f == 8 || f == 9) {
        if (f == 1 || f == 9) {
          b.blob(1.05, 1.05, .08, 0, 1.48, -.33, c.frame);
          b.blob(.94, .94, .025, 0, 1.48, -.28, c.glass);
        } else {
          b.box(1.25, .9, .08, 0, 1.42, -.33, c.frame);
          b.box(1.1, .76, .02, 0, 1.42, -.28, c.glass);
          for (final x in [-.85, .85]) {
            b.box(.3, .65, .08, x, 1.4, -.3, c.glass);
          }
        }
      }
      if (f == 4 || f == 7) {
        for (final x in [-1.23, 1.23]) {
          b.box(.07, .94, .4, x, 1.3, -.19, c.frame);
        }
        for (final y in [1.15, 1.75]) {
          b.box(2.5, .06, .4, 0, y, -.19, c.surface);
        }
      }
      if (f == 0) {
        b.drawer(.85, .14, 0, .68, .42);
      }
    case RoomItemVisualKind.ottoman:
      final wide = [2, 3, 4, 9].contains(f);
      final w = wide ? 1.8 : .82;
      if (f == 4) {
        b.legs(w, .65, .45);
        for (var i = 0; i < 4; i++) {
          b.box(w, .06, .14, 0, .48, -.24 + i * .16, c.surface);
        }
      } else if (f == 7) {
        for (var i = 0; i < 3; i++) {
          final a = i * math.pi * 2 / 3;
          b.cyl(.03, .47, math.cos(a) * .22, .235, math.sin(a) * .22, c.frame);
        }
        b.top(.72, .72, .5, round: true);
      } else {
        b.legs(w, .7, .14);
        if (f == 0 || f == 5 || f == 6) {
          final body = furnitureCylinder(
            radiusTop: .4,
            radiusBottom: f == 6 ? .34 : .4,
            height: .35,
            color: c.frame,
            y: .31,
          );
          if (f == 5) {
            body.scale.x = 1.12;
          }
          b.group.add(body);
          b.blob(f == 5 ? .9 : .83, .2, .8, 0, .5, 0, c.soft);
          if (f == 6) {
            for (var i = 0; i < 14; i++) {
              final a = i * math.pi / 7;
              b.cyl(
                .012,
                .3,
                .39 * math.cos(a),
                .31,
                .39 * math.sin(a),
                c.accent,
                sides: 6,
              );
            }
          }
        } else {
          b.box(w, .28, .72, 0, .28, 0, c.frame);
          b.blob(w + .05, .24, .78, 0, .49, 0, c.soft);
          if (f == 2) {
            b.box(w, .025, .74, 0, .42, 0, c.hardware);
          }
          if (f == 3) {
            for (final x in [-.6, -.2, .2, .6]) {
              b.blob(.05, .025, .05, x, .606, 0, c.hardware);
            }
          }
          if (f == 8) {
            b.blob(.3, .18, .72, -.3, .53, 0, c.soft);
          }
          if (f == 9) {
            for (final x in [-.75, .75]) {
              b.blob(.28, .28, .7, x, .65, 0, c.accent);
            }
          }
        }
      }
    case RoomItemVisualKind.floorLamp:
      final h = f == 7 || f == 8 ? .85 : 1.85;
      b.cyl(.22, .06, 0, .03, 0, c.frame);
      if (f == 1) {
        for (var i = 0; i < 3; i++) {
          final a = i * 2 * math.pi / 3;
          b.cyl(
            .025,
            1.5,
            math.cos(a) * .15,
            .75,
            math.sin(a) * .15,
            c.frame,
            tilt: math.cos(a) * .14,
          );
        }
      } else {
        b.cyl(.025, h - .2, 0, h / 2 - .04, 0, c.hardware);
      }
      if (f == 2) {
        var point = three.Vector3(0, h - .2, 0);
        for (var i = 1; i <= 12; i++) {
          final t = i / 12;
          final next = three.Vector3(
            .82 * t,
            h - .2 + math.sin(t * math.pi) * .3,
            0,
          );
          b.rod(point, next, .025, c.hardware);
          point = next;
        }
        b.cyl(.18, .18, .82, h - .27, 0, c.accent, bottom: .3);
      } else if (f == 3 || f == 5 || f == 9) {
        if (f == 9) {
          for (var i = 0; i < 3; i++) {
            final x = (i - 1) * .25;
            b.box(.5, .025, .025, 0, 1.3 + i * .2, 0, c.hardware);
            b.blob(.26, .26, .26, x, 1.43 + i * .2, 0, c.accent);
          }
        } else {
          b.blob(.6, f == 5 ? .8 : .6, .6, 0, h - .2, 0, c.accent);
          if (f == 5) {
            for (var i = 0; i < 6; i++) {
              b.cyl(
                .29 * math.sin((i + 1) * math.pi / 7),
                .013,
                0,
                h - .53 + i * .13,
                0,
                c.soft,
              );
            }
          }
        }
      } else if (f == 4) {
        b.box(.65, .035, .035, 0, 1.55, 0, c.hardware);
        for (final x in [-.3, .3]) {
          b.cyl(.1, .24, x, 1.72, 0, c.accent, bottom: .19);
        }
      } else {
        b.cyl(f == 7 ? .28 : .17, .32, 0, h - .08, 0, c.accent, bottom: .32);
        if (f == 7) {
          b.blob(.7, .35, .7, 0, h + .07, 0, c.accent);
        }
        if (f == 8) {
          b.box(.44, .035, .035, .15, .68, 0, c.hardware);
        }
      }
      if (f == 6) {
        for (final y in [.4, .8, 1.2]) {
          b.top(.65, .65, y);
        }
      }
    case RoomItemVisualKind.plant:
      final potY = f == 9 ? .38 : 0.0;
      if (f == 9) {
        b.legs(.55, .55, .38);
      }
      b.cyl(f == 7 ? .38 : .25, .4, 0, potY + .2, 0, c.frame, bottom: .18);
      b.cyl(f == 7 ? .35 : .23, .025, 0, potY + .405, 0, c.surface);
      if (design.finish == 2) {
        for (var i = 0; i < 18; i++) {
          final a = i * math.pi / 9;
          b.cyl(
            .013,
            .34,
            .225 * math.cos(a),
            potY + .23,
            .225 * math.sin(a),
            c.accent,
            sides: 6,
          );
        }
      }
      if (f == 2) {
        b.cyl(.12, 1, 0, .9, 0, c.soft, bottom: .13);
        for (final x in [-.24, .24]) {
          b.box(.3, .12, .12, x / 2, .85, 0, c.soft);
          b.cyl(.08, .38, x, 1.0, 0, c.soft);
        }
      } else if (f == 1 || f == 5) {
        for (var i = 0; i < 7; i++) {
          final x = math.sin(i * 2.4) * .18, z = math.cos(i * 2.4) * .18;
          final h = .65 + (i % 3) * .22;
          if (f == 5) {
            b.cyl(.025, h, x, .42 + h / 2, z, c.soft);
            for (var j = 0; j < 4; j++) {
              b.blob(.28, .06, .12, x + .08, .6 + j * .2, z, c.soft);
            }
          } else {
            b.blob(.12, h, .065, x, .4 + h / 2, z, c.soft);
          }
        }
      } else if (f == 7) {
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          b.blob(
            .27,
            .15,
            .16,
            math.cos(a) * .2,
            .49,
            math.sin(a) * .2,
            c.soft,
          );
        }
        b.blob(.25, .23, .25, 0, .56, 0, c.hardware);
      } else {
        final h = f == 3 || f == 6 || f == 8 ? 1.55 : 1.15;
        b.cyl(.035, h - .4, 0, .4 + (h - .4) / 2, 0, c.hardware);
        if (f == 8) {
          b.blob(.62, .62, .62, 0, h, 0, c.soft);
          b.blob(.42, .42, .42, 0, h + .45, 0, furnitureShade(c.soft, .1));
        } else {
          final n = f == 0 || f == 9 ? 9 : 6;
          for (var i = 0; i < n; i++) {
            final a = i * math.pi * 2 / n;
            final y = h - (i % 3) * .18 + potY;
            b.blob(
              f == 3 ? .28 : .46,
              f == 6 ? .3 : .09,
              f == 4 ? .32 : .2,
              math.cos(a) * .22,
              y,
              math.sin(a) * .22,
              furnitureShade(c.soft, (i % 3) * .045),
            );
            b.cyl(
              .012,
              .35,
              math.cos(a) * .12,
              y - .13,
              math.sin(a) * .12,
              c.hardware,
              tilt: math.cos(a) * .5,
              sides: 6,
            );
          }
        }
      }
    case RoomItemVisualKind.chair:
      final seat = f == 5 ? .8 : .48;
      if (f == 3) {
        for (final x in [-.3, .3]) {
          b.box(.035, seat, .035, x, seat / 2, .25, c.hardware);
          b.box(.035, .035, .65, x, .025, 0, c.hardware);
        }
      } else {
        b.legs(.72, .7, seat);
      }
      if (f == 6) {
        b.blob(.8, .22, .75, 0, seat, 0, c.soft);
      } else {
        b.box(
          .73,
          .09,
          .7,
          0,
          seat,
          0,
          f == 0 || f == 4 || f == 7 ? c.surface : c.soft,
        );
      }
      final backY = seat + .35;
      if (f == 0 || f == 4 || f == 7) {
        for (final x in [-.31, .31]) {
          b.box(.045, .65, .05, x, backY, -.29, c.frame);
        }
        b.box(.72, .08, .06, 0, seat + .64, -.29, c.frame);
        if (f == 0) {
          for (var i = 0; i < 5; i++) {
            b.cyl(.018, .5, -.24 + i * .12, backY, -.29, c.frame, sides: 8);
          }
        }
        if (f == 4) {
          for (final t in [-.7, .7]) {
            b.box(.035, .7, .04, 0, backY, -.29, c.frame, tilt: t);
          }
        }
        if (f == 7) {
          for (var i = 0; i < 3; i++) {
            b.box(.6, .08, .05, 0, seat + .18 + i * .16, -.29, c.surface);
          }
        }
      } else if (f != 5) {
        b.blob(.78, .67, .16, 0, backY, -.28, c.soft);
      }
      if (f == 2 || f == 8 || f == 9) {
        for (final x in [-.35, .35]) {
          b.box(.06, .22, .06, x, seat + .12, .16, c.frame);
          b.box(.1, .06, .65, x, seat + .25, 0, c.frame);
        }
      }
      if (f == 8) {
        for (final x in [-.31, .31]) {
          b.blob(.08, .11, .95, x, .055, 0, c.frame);
        }
      }
      if (f == 9) {
        b.blob(.72, .16, .5, 0, .36, .39, c.soft);
      }
      if (f == 5) {
        b.box(.58, .035, .035, 0, .3, .28, c.hardware);
      }
    case RoomItemVisualKind.sofa:
      final w = f == 0 ? 2.3 : 3.35;
      b.legs(w, 1.25, .18);
      b.box(w, .25, 1.25, 0, .3, 0, c.frame);
      final n = f == 0 ? 2 : 3;
      for (var i = 0; i < n; i++) {
        final x = -w / 2 + .2 + (i + .5) * (w - .4) / n;
        b.cushion((w - .4) / n - .025, .3, 1.05, x, .55, .06, c.soft);
        if (f != 8) {
          b.cushion(
            (w - .35) / n,
            .76,
            .3,
            x,
            .9 + (f == 9 ? math.cos(i * 2.0) * .08 : 0),
            -.48,
            c.soft,
          );
        }
      }
      if (f != 7) {
        for (final x in [-w / 2 + .1, w / 2 - .1]) {
          if (f == 6) {
            b.blob(.4, .55, 1.25, x, .7, 0, c.accent);
          } else {
            b.box(
              .2,
              f == 5 ? .85 : .5,
              1.25,
              x,
              f == 5 ? .72 : .55,
              0,
              c.soft,
            );
          }
        }
      }
      if (f == 2 || f == 3 || f == 4) {
        final x = f == 3 ? w / 2 - .7 : -w / 2 + .7;
        b.box(1.15, .35, 1.1, x, .3, 1.05, c.frame);
        b.cushion(1.15, .3, 1.1, x, .55, 1.05, c.soft);
        b.legs(1.15, 1.1, .15, x: x, z: 1.05);
        if (f == 4) {
          b.box(.2, .8, 1.1, x - .47, .7, 1.05, c.soft);
        }
      }
      if (f == 8) {
        b.blob(.35, .35, 1.0, -w / 2 + .35, .83, 0, c.accent);
      }
      if (f == 9) {
        for (final x in [-w / 2 + .2, w / 2 - .2]) {
          b.blob(.65, .8, 1.2, x, .7, -.1, c.soft);
        }
      }
    case RoomItemVisualKind.bookshelf:
      final h = f == 3 || f == 6 ? .9 : 2.3;
      final w = f == 1 ? 1.4 : 2.5;
      b.legs(w, .75, .12);
      if (f != 9) {
        b.box(
          w,
          h - .15,
          .04,
          0,
          h / 2 + .1,
          -.35,
          furnitureShade(c.frame, -.12),
        );
      }
      for (final x in [-w / 2, w / 2]) {
        b.box(.07, h, .74, x, h / 2 + .12, 0, c.frame, tilt: f == 1 ? -.1 : 0);
      }
      final levels = f == 3 || f == 6 ? 2 : 5;
      for (var i = 0; i <= levels; i++) {
        final y = .15 + i * (h - .1) / levels;
        final shelfW = f == 8 ? w * (1 - i * .1) : w;
        b.box(shelfW, .055, f == 1 ? .72 - i * .08 : .74, 0, y, 0, c.surface);
        if (i < levels) {
          if (f == 2 || f == 4 || f == 9) {
            b.box(
              .05,
              (h - .1) / levels,
              .7,
              f == 4 ? (i.isEven ? -.4 : .4) : 0,
              y + (h - .1) / levels / 2,
              0,
              c.frame,
            );
          }
          if (f != 6) {
            for (var j = 0; j < 3; j++) {
              b.box(
                .09 + j * .025,
                .21 + j * .03,
                .22,
                -shelfW / 2 + .18 + j * .13,
                y + .14,
                .1,
                [c.accent, c.soft, c.hardware][j],
              );
            }
          }
        }
      }
      if (f == 6 || f == 7) {
        for (final x in [-.62, .62]) {
          b.box(
            1.17,
            h - .15,
            .04,
            x,
            h / 2 + .1,
            .4,
            f == 7 ? c.glass : c.surface,
          );
          if (design.finish == 1 || f == 6) {
            b.cane(1.0, h - .3, x, h / 2 + .1, .43);
          }
          b.box(.04, .2, .05, x + .4, h / 2, .46, c.hardware);
        }
      }
      if (f == 5) {
        b.blob(w, .6, .74, 0, h + .04, 0, c.frame);
      }
  }
  return b.group;
}
