import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;

class PhotoSaveException implements Exception {
  const PhotoSaveException(this.message);
  final String message;
}

/// Saves the source photo, rather than a screenshot or the resized avatar.
class PhotoGallerySaver {
  const PhotoGallerySaver({http.Client? client}) : _client = client;
  final http.Client? _client;

  Future<void> save(
    ImageProvider image, {
    ImageConfiguration configuration = ImageConfiguration.empty,
  }) async {
    try {
      if (!await Gal.requestAccess()) {
        throw const PhotoSaveException(
          'Allow photo access in Settings to save photos.',
        );
      }
      final bytes = await _read(image, configuration);
      if (bytes.isEmpty) {
        throw const PhotoSaveException('Photo could not be loaded. Try again.');
      }
      await Gal.putImageBytes(
        bytes,
        name: 'BackHome_${DateTime.now().microsecondsSinceEpoch}',
      );
    } on GalException catch (error) {
      throw PhotoSaveException(switch (error.type) {
        GalExceptionType.accessDenied =>
          'Allow photo access in Settings to save photos.',
        GalExceptionType.notEnoughSpace =>
          'Not enough space to save this photo.',
        GalExceptionType.notSupportedFormat =>
          'This photo format cannot be saved.',
        GalExceptionType.unexpected => 'Could not save photo. Try again.',
      });
    }
  }

  Future<Uint8List> _read(
    ImageProvider image,
    ImageConfiguration configuration,
  ) async {
    if (image is ResizeImage) return _read(image.imageProvider, configuration);
    if (image is MemoryImage) return image.bytes;
    if (image is FileImage) return image.file.readAsBytes();
    if (image is AssetBundleImageProvider) {
      final key = await image.obtainKey(configuration);
      final data = await key.bundle.load(key.name);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    if (image is NetworkImage) {
      final uri = Uri.parse(image.url);
      final response =
          await (_client?.get(uri, headers: image.headers) ??
                  http.get(uri, headers: image.headers))
              .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw const PhotoSaveException('Photo could not be loaded. Try again.');
      }
      return response.bodyBytes;
    }
    throw const PhotoSaveException('This photo cannot be saved.');
  }
}
