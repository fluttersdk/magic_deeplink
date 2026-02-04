import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_deeplink/src/handlers/deeplink_handler.dart';

class TestDeeplinkHandler extends DeeplinkHandler {
  @override
  bool canHandle(Uri uri) => uri.path == '/test';

  @override
  Future<bool> handle(Uri uri) async => true;
}

void main() {
  group('DeeplinkHandler', () {
    test('contract defines required methods', () async {
      final handler = TestDeeplinkHandler();
      final uri = Uri.parse('https://example.com/test');

      expect(handler.canHandle(uri), isTrue);
      expect(await handler.handle(uri), isTrue);
    });
  });
}
