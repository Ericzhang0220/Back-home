import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';

class AiCharacterPhoto {
  const AiCharacterPhoto({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
  static const maxBytes = 10 * 1024 * 1024;

  static Future<AiCharacterPhoto?> pickFromGallery() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1536,
      maxHeight: 2048,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (image == null) return null;
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Choose an image smaller than 10 MB.');
    }
    // Validate actual image bytes before enabling creation, including files
    // selected through the desktop file chooser.
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
    final header = String.fromCharCodes(bytes.take(12));
    final type = bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8
        ? 'image/jpeg'
        : header.startsWith('\u0089PNG')
        ? 'image/png'
        : header.startsWith('GIF8')
        ? 'image/gif'
        : header.startsWith('RIFF') && header.endsWith('WEBP')
        ? 'image/webp'
        : image.mimeType ?? 'image/jpeg';
    return AiCharacterPhoto(bytes: bytes, contentType: type);
  }
}
