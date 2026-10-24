// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:back_home/rooms/isometric_room_view.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:flutter/material.dart';

/// Isolated preview of the room's outside (window) view for visual tuning.
///
/// flutter run -t tool/outside_preview.dart \
///   --dart-define=PREVIEW_CONFIG=/abs/path/preview.json
///
/// The JSON file is re-read on every hot restart:
/// {"time": 0.5, "weather": "clear", "outside": true, "yaw": 0.3, "pitch": -0.1}
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const configPath = String.fromEnvironment('PREVIEW_CONFIG');
  var config = <String, dynamic>{};
  if (configPath.isNotEmpty && File(configPath).existsSync()) {
    config =
        jsonDecode(File(configPath).readAsStringSync()) as Map<String, dynamic>;
  }
  final time = (config['time'] as num?)?.toDouble() ?? 0.5;
  final weather = SkyWeather.values.firstWhere(
    (value) => value.name == config['weather'],
    orElse: () => SkyWeather.clear,
  );
  final yaw = (config['yaw'] as num?)?.toDouble();
  IsometricRoomView.debugOutsideLook = yaw == null
      ? null
      : (yaw: yaw, pitch: (config['pitch'] as num?)?.toDouble() ?? -0.05);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: IsometricRoomView(
          key: UniqueKey(),
          controller: RoomEditorController(),
          isActive: true,
          outsideView: config['outside'] as bool? ?? true,
          skyWeather: weather,
          skyTimeOfDay: time,
        ),
      ),
    ),
  );
}
