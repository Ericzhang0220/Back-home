import 'package:back_home/rooms/outdoor_landscape.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js/three_js.dart' as three;

void main() {
  const noon = OutdoorLight(
    sunX: 0,
    sunY: 0.8,
    sunZ: 0.6,
    sun: 0xFFF3D4,
    sunStrength: 0.78,
    sky: 0xC4DCF4,
    ground: 0xC79C5A,
    ambientStrength: 0.54,
    fog: 0xA7D2EF,
    fogAmount: 0.72,
    shadowStrength: 0.7,
    saturation: 1,
    windowGlow: 0,
  );

  test('landscape relights to valid colours without rebuilding geometry', () {
    final landscape = OutdoorLandscape(wallZ: -8);
    addTearDown(landscape.group.dispose);
    landscape.relight(noon);

    final meshes = landscape.group.children.whereType<three.Mesh>().toList();
    expect(meshes, isNotEmpty);
    for (final mesh in meshes) {
      final colors = mesh.geometry!.getAttributeFromString('color');
      final values = colors.array.toDartList();
      expect(values, isNotEmpty);
      for (final value in values) {
        expect(value.isFinite && value >= 0 && value <= 1, isTrue);
      }
    }
  });

  test('meadow outside the window sits above the sea', () {
    final landscape = OutdoorLandscape(wallZ: -8);
    addTearDown(landscape.group.dispose);
    for (final u in [-3.0, 0.0, 3.0]) {
      expect(
        landscape.height(u, 1),
        greaterThan(OutdoorLandscape.seaLevel + 2),
      );
    }
  });
}
