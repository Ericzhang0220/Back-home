import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/photo_gallery_saver.dart';

Future<void> showFullscreenPhoto(
  BuildContext context, {
  required ImageProvider image,
  required String label,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => FullscreenPhotoViewer(image: image, label: label),
  ),
);

/// A single photo with pinch zoom and a downward swipe to close at normal zoom.
class FullscreenPhotoViewer extends StatefulWidget {
  const FullscreenPhotoViewer({
    super.key,
    required this.image,
    required this.label,
  });
  final ImageProvider image;
  final String label;

  @override
  State<FullscreenPhotoViewer> createState() => _FullscreenPhotoViewerState();
}

class _FullscreenPhotoViewerState extends State<FullscreenPhotoViewer> {
  final _transform = TransformationController();
  final _pointers = <int>{};
  Offset? _start;
  double _drag = 0;
  bool _menuOpen = false;
  bool _saving = false;

  Future<void> _showPhotoActions() async {
    if (_menuOpen || _saving) return;
    setState(() {
      _menuOpen = true;
      _start = null;
      _drag = 0;
    });
    final save = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xfffcf7f1),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.save_alt_rounded),
                title: const Text('Save to Photos'),
                onTap: () => Navigator.of(context).pop(true),
              ),
              ListTile(
                title: const Text('Cancel', textAlign: TextAlign.center),
                onTap: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (save == true) await _savePhoto();
  }

  Future<void> _savePhoto() async {
    setState(() => _saving = true);
    var message = 'Saved to Photos';
    final configuration = createLocalImageConfiguration(context);
    try {
      await const PhotoGallerySaver().save(
        widget.image,
        configuration: configuration,
      );
    } on PhotoSaveException catch (error) {
      message = error.message;
    } catch (_) {
      message = 'Could not save photo. Check your connection and try again.';
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _end(int pointer) {
    _pointers.remove(pointer);
    if (!_menuOpen && _drag > 90) {
      Navigator.of(context).pop();
    } else if (_drag != 0) {
      setState(() => _drag = 0);
    }
    _start = null;
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              onPointerDown: (event) {
                _pointers.add(event.pointer);
                _start =
                    _pointers.length == 1 &&
                        _transform.value.getMaxScaleOnAxis() <= 1.01
                    ? event.position
                    : null;
                if (_pointers.length > 1 && _drag != 0) {
                  setState(() => _drag = 0);
                }
              },
              onPointerMove: (event) {
                if (_menuOpen ||
                    _start == null ||
                    _pointers.length != 1 ||
                    _transform.value.getMaxScaleOnAxis() > 1.01) {
                  return;
                }
                final delta = event.position - _start!;
                if ((delta.dy > 12 && delta.dy > delta.dx.abs() * 1.3) ||
                    _drag > 0) {
                  setState(() => _drag = delta.dy.clamp(0, double.infinity));
                }
              },
              onPointerUp: (event) => _end(event.pointer),
              onPointerCancel: (event) {
                _pointers.remove(event.pointer);
                _start = null;
                setState(() => _drag = 0);
              },
              child: AnimatedSlide(
                offset: Offset(0, _drag / MediaQuery.sizeOf(context).height),
                duration: _drag == 0
                    ? const Duration(milliseconds: 180)
                    : Duration.zero,
                child: InteractiveViewer(
                  transformationController: _transform,
                  minScale: 1,
                  maxScale: 5,
                  child: GestureDetector(
                    onLongPress: _showPhotoActions,
                    child: SizedBox.expand(
                      child: Image(
                        image: widget.image,
                        fit: BoxFit.contain,
                        semanticLabel: widget.label,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_saving)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: SafeArea(
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Saving…'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Close photo',
                onPressed: () => Navigator.of(context).pop(),
                color: Colors.white,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
