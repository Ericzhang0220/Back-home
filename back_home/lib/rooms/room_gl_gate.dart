import 'package:flutter/widgets.dart';

/// Arbitrates the one live 3D renderer the app is allowed to have.
///
/// The mobile GL backend can't safely keep two renderers alive at once — a
/// second context leaves the first wedged (the symptom was a frozen room camera
/// after every edit). This started as a single "an editor is open" flag; the
/// shop's 3D previews are a third screen that wants the context, and the editor
/// can be pushed from *on top of* the shop, so ownership is a stack rather than
/// a bool.
///
/// The screen that owns the top claim renders; everyone below it releases and
/// shows a still fallback. Claims are keyed by identity — hand in a private
/// `Object()` from your State and release it in `dispose`.
class RoomGlGate {
  RoomGlGate._();

  /// The token currently allowed to render, or null when the background room
  /// view may run. Listen to this to release/rebuild a renderer.
  static final ValueNotifier<Object?> activeOwner = ValueNotifier<Object?>(null);

  static final List<Object> _claims = <Object>[];

  /// True when [token] is the top claim and may hold a GL context.
  static bool holds(Object token) =>
      _claims.isNotEmpty && identical(_claims.last, token);

  static void claim(Object token) {
    if (_claims.any((claim) => identical(claim, token))) {
      return;
    }
    _claims.add(token);
    _publish();
  }

  static void release(Object token) {
    final before = _claims.length;
    _claims.removeWhere((claim) => identical(claim, token));
    if (_claims.length != before) {
      _publish();
    }
  }

  static void _publish() {
    // Deferred out of the current frame on purpose. Claims and releases happen
    // in initState/dispose, and writing the notifier inline would rebuild the
    // listening screens mid-build — racing a renderer's ticker into a
    // half-torn-down EGL context. Post-frame callbacks also preserve ordering,
    // so a claim immediately followed by a release still settles correctly.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      activeOwner.value = _claims.isEmpty ? null : _claims.last;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}
