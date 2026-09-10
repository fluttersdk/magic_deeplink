import 'package:flutter_test/flutter_test.dart';
import 'package:magic_deeplink/src/handlers/deeplink_handler.dart';

class TestDeeplinkHandler extends DeeplinkHandler {
  /// The provenance the last call arrived with.
  DeeplinkSource? handledSource;

  /// The payload the last call arrived with.
  Map<String, dynamic>? handledPayload;

  @override
  bool canHandle(Uri uri) => uri.path == '/test';

  @override
  Future<bool> handle(
    Uri uri, {
    required DeeplinkSource source,
    Map<String, dynamic>? payload,
  }) async {
    handledSource = source;
    handledPayload = payload;

    return true;
  }
}

void main() {
  group('DeeplinkHandler', () {
    test('contract defines required methods', () async {
      final handler = TestDeeplinkHandler();
      final uri = Uri.parse('https://example.com/test');

      expect(handler.canHandle(uri), isTrue);
      expect(
        await handler.handle(uri, source: DeeplinkSource.osLink),
        isTrue,
      );
    });

    test('the contract carries provenance and the payload behind it', () async {
      final handler = TestDeeplinkHandler();
      final uri = Uri.parse('https://example.com/test');

      await handler.handle(
        uri,
        source: DeeplinkSource.push,
        payload: {'deep_link': '/test', 'team_id': 't-9'},
      );

      expect(handler.handledSource, DeeplinkSource.push);
      expect(handler.handledPayload, {'deep_link': '/test', 'team_id': 't-9'});
    });

    test('an OS link carries no payload for a handler to trust', () async {
      final handler = TestDeeplinkHandler();

      await handler.handle(
        Uri.parse('https://example.com/test'),
        source: DeeplinkSource.osLink,
      );

      expect(handler.handledSource, DeeplinkSource.osLink);
      expect(handler.handledPayload, isNull);
    });
  });
}
