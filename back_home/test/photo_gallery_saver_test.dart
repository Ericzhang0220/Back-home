import 'package:back_home/chat/photo_gallery_saver.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final saved = <Uint8List>[];
  setUp(() {
    saved.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('gal'), (call) async {
          if (call.method == 'requestAccess') return true;
          if (call.method == 'putImageBytes') {
            saved.add(call.arguments['bytes'] as Uint8List);
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('gal'), null);
  });

  test('bundled character saves the full source asset', () async {
    const photo = AssetImage('assets/ai_characters/noah-carter.png');
    final data = await rootBundle.load(photo.assetName);
    await const PhotoGallerySaver().save(ResizeImage(photo, width: 256));
    expect(saved.single, orderedEquals(data.buffer.asUint8List()));
  });

  test(
    'uploaded photo saves the original response and forwards headers',
    () async {
      final bytes = Uint8List.fromList([0xff, 0xd8, 0xff, 1, 2]);
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://example.test/portrait.jpg');
        expect(request.headers['authorization'], 'photo-token');
        return http.Response.bytes(bytes, 200);
      });
      await PhotoGallerySaver(client: client).save(
        const NetworkImage(
          'https://example.test/portrait.jpg',
          headers: {'authorization': 'photo-token'},
        ),
      );
      expect(saved.single, orderedEquals(bytes));
      client.close();
    },
  );

  test('failed download never writes an error response into Photos', () async {
    final client = MockClient((_) async => http.Response('missing', 404));
    await expectLater(
      PhotoGallerySaver(
        client: client,
      ).save(const NetworkImage('https://example.test/missing.jpg')),
      throwsA(isA<PhotoSaveException>()),
    );
    expect(saved, isEmpty);
    client.close();
  });
}
