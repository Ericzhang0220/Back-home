import 'package:flutter/material.dart';

/// Shared artwork renderer for discovery cards, contact avatars and profiles.
/// An uploaded portrait takes precedence; bundled art survives network errors.
class CharacterPortrait extends StatelessWidget {
  const CharacterPortrait({
    super.key,
    required this.fallback,
    this.photoUrl,
    this.assetPath,
    this.assetAlignment = Alignment.topCenter,
    this.semanticLabel,
    this.cacheWidth,
  });

  final String? photoUrl;
  final String? assetPath;
  final Alignment assetAlignment;
  final String? semanticLabel;
  final int? cacheWidth;
  final Widget fallback;

  Widget _bundledPortrait() {
    if (assetPath == null) {
      return fallback;
    }
    return Image.asset(
      assetPath!,
      fit: BoxFit.cover,
      alignment: assetAlignment,
      semanticLabel: semanticLabel,
      cacheWidth: cacheWidth,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim();
    if (url == null || url.isEmpty) {
      return _bundledPortrait();
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      semanticLabel: semanticLabel,
      cacheWidth: cacheWidth,
      errorBuilder: (context, error, stackTrace) => _bundledPortrait(),
    );
  }
}
