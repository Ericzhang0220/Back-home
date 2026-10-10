import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lets AI and Human artwork fill the status bar while keeping the interactive
/// card in the same safe rectangle as the tabs and other chat screens.
class DiscoveryCardSurface extends StatelessWidget {
  const DiscoveryCardSurface({
    super.key,
    required this.background,
    required this.foreground,
  });

  final Widget background;
  final Widget foreground;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          background,
          SafeArea(bottom: false, child: foreground),
        ],
      ),
    );
  }
}
