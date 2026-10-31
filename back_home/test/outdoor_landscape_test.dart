import 'package:back_home/rooms/outdoor_landscape.dart';
import 'package:back_home/rooms/room_state.dart';
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
  const night = OutdoorLight(
    sunX: 0.3,
    sunY: 0.5,
    sunZ: 0.6,
    sun: 0x9FB4E2,
    sunStrength: 0.3,
    sky: 0x34467A,
    ground: 0x202232,
    ambientStrength: 0.28,
    fog: 0x141D33,
    fogAmount: 0.72,
    shadowStrength: 0.2,
    saturation: 0.7,
    windowGlow: 0.9,
    daylight: 0,
  );

  for (final environment in OutdoorEnvironment.values) {
    test('${environment.name} relights and animates with valid colours', () {
      final scene = OutdoorScene.build(environment, wallZ: -8);
      addTearDown(scene.group.dispose);
      for (final light in [noon, night]) {
        scene
          ..relight(light)
          ..animate(0.5);
        final meshes = scene.group.children.whereType<three.Mesh>().where(
          (mesh) => mesh.geometry!.getAttributeFromString('color') != null,
        );
        expect(meshes, isNotEmpty);
        for (final mesh in meshes) {
          final values = mesh.geometry!
              .getAttributeFromString('color')
              .array
              .toDartList();
          for (final value in values) {
            expect(value.isFinite && value >= 0 && value <= 1, isTrue);
          }
        }
      }
    });
  }

  test('meadow outside the window sits above the sea', () {
    final landscape = IslandScene(wallZ: -8);
    addTearDown(landscape.group.dispose);
    for (final u in [-3.0, 0.0, 3.0]) {
      expect(landscape.height(u, 1), greaterThan(IslandScene.seaLevel + 2));
    }
  });
}
