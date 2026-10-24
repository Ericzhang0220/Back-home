import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Stops UIKit's three-finger Undo/Redo HUD from competing with camera panning.
/// Owners keep overlapping room/editor lifetimes from restoring it too early.
class IosRoomGesturePolicy {
  IosRoomGesturePolicy._();

  static const _channel = MethodChannel('back_home/room_gestures');
  static final Set<Object> _owners = {};

  static void setActive(Object owner, bool active) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final wasActive = _owners.isNotEmpty;
    if (active) {
      _owners.add(owner);
    } else {
      _owners.remove(owner);
    }
    final isActive = _owners.isNotEmpty;
    if (wasActive != isActive) {
      unawaited(_publish(isActive));
    }
  }

  static Future<void> _publish(bool active) async {
    try {
      await _channel.invokeMethod<void>('setRoomGesturesActive', {
        'active': active,
      });
    } on MissingPluginException {
      // Hot reload cannot install the native controller into an older binary.
      debugPrint('Rebuild the iOS app to enable room gesture isolation.');
    } on PlatformException catch (error) {
      debugPrint('Could not update iOS room gestures: ${error.code}');
    }
  }
}
