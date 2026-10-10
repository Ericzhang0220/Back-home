import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChatBackgroundMode { portrait, photo, plain }

class ChatBackgroundChoice {
  const ChatBackgroundChoice(this.mode, {this.photoPath});
  final ChatBackgroundMode mode;
  final String? photoPath;
}

/// Personal appearance settings, scoped to account, directory and conversation.
/// Photos live in application support rather than the gallery picker's cache.
class ChatBackgroundStore {
  ChatBackgroundStore({
    Future<Directory> Function()? directory,
    Future<SharedPreferences> Function()? preferences,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<Directory> Function() _directory;
  final Future<SharedPreferences> Function() _preferences;

  String _scope(String uid, bool isAi, String peerId) => sha256
      .convert(utf8.encode(jsonEncode([uid, isAi ? 'ai' : 'user', peerId])))
      .toString();

  Future<Directory> _folder() async => Directory(
    '${(await _directory()).path}/chat_backgrounds',
  ).create(recursive: true);

  Future<ChatBackgroundChoice> load({
    required String uid,
    required bool isAi,
    required String peerId,
  }) async {
    final fallback = ChatBackgroundChoice(
      isAi ? ChatBackgroundMode.portrait : ChatBackgroundMode.plain,
    );
    final scope = _scope(uid, isAi, peerId);
    final raw = (await _preferences()).getString('chat_background_$scope');
    if (raw == null) return fallback;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final mode = ChatBackgroundMode.values.byName(data['mode'] as String);
      if (mode != ChatBackgroundMode.photo) return ChatBackgroundChoice(mode);
      final name = data['file'] as String;
      if (!_validFile(name, scope)) return fallback;
      final file = File('${(await _folder()).path}/$name');
      return await file.exists()
          ? ChatBackgroundChoice(mode, photoPath: file.path)
          : fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<ChatBackgroundChoice> save({
    required String uid,
    required bool isAi,
    required String peerId,
    required ChatBackgroundMode mode,
    Uint8List? photo,
  }) async {
    if (mode == ChatBackgroundMode.photo &&
        (photo == null || photo.isEmpty || photo.length > 10 * 1024 * 1024)) {
      throw ArgumentError('Choose a photo smaller than 10 MB.');
    }
    final scope = _scope(uid, isAi, peerId);
    final preferences = await _preferences();
    final key = 'chat_background_$scope';
    final old = preferences.getString(key);
    File? file;
    try {
      if (mode == ChatBackgroundMode.photo) {
        file = File(
          '${(await _folder()).path}/${scope}_${DateTime.now().microsecondsSinceEpoch}.img',
        );
        await file.writeAsBytes(photo!, flush: true);
      }
      final saved = await preferences.setString(
        key,
        jsonEncode({
          'mode': mode.name,
          if (file != null) 'file': file.uri.pathSegments.last,
        }),
      );
      if (!saved) throw StateError('Could not save the background.');
    } catch (_) {
      if (file != null) await _remove(file);
      rethrow;
    }
    // Remove only the previous image belonging to this exact conversation,
    // after its replacement has been durably saved.
    if (old != null) {
      try {
        final name = (jsonDecode(old) as Map<String, dynamic>)['file'];
        if (name is String && _validFile(name, scope)) {
          await _remove(File('${(await _folder()).path}/$name'));
        }
      } catch (_) {}
    }
    return ChatBackgroundChoice(mode, photoPath: file?.path);
  }

  bool _validFile(String name, String scope) =>
      name.startsWith('${scope}_') &&
      RegExp(r'^[a-f0-9]+_[0-9]+\.img$').hasMatch(name);

  Future<void> _remove(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      /* Appearance remains usable if cleanup fails. */
    }
  }
}
