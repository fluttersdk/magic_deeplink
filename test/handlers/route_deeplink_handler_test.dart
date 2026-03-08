import 'package:flutter_test/flutter_test.dart';
import 'package:magic_deeplink/src/handlers/route_deeplink_handler.dart';

void main() {
  group('RouteDeeplinkHandler', () {
    late RouteDeeplinkHandler handler;

    setUp(() {
      handler = RouteDeeplinkHandler(paths: [
        '/monitors/*',
        '/settings',
        '/teams/:id',
      ]);
    });

    test('canHandle matches exact paths', () {
      expect(
          handler.canHandle(Uri.parse('https://example.com/settings')), isTrue);
      expect(handler.canHandle(Uri.parse('https://example.com/settings/')),
          isTrue); // Trailing slash handling
    });

    test('canHandle matches wildcard paths', () {
      expect(handler.canHandle(Uri.parse('https://example.com/monitors/123')),
          isTrue);
      expect(handler.canHandle(Uri.parse('https://example.com/monitors/new')),
          isTrue);
    });

    test('canHandle matches parameter paths', () {
      // Simple wildcard matching usually treats :id as * or specific segment
      // For this implementation, we'll assume basic wildcard support or regex
      expect(
          handler.canHandle(Uri.parse('https://example.com/teams/5')), isTrue);
    });

    test('canHandle rejects non-matching paths', () {
      expect(
          handler.canHandle(Uri.parse('https://example.com/unknown')), isFalse);
      expect(
          handler.canHandle(Uri.parse('https://example.com/settings/profile')),
          isFalse); // Exact match failed
    });

    test('handle attempts to navigate via MagicRoute', () async {
      final uri = Uri.parse('https://example.com/some/path');
      // Since MagicRouter is not initialized in this unit test environment,
      // it throws a StateError. Catching this error confirms that MagicRoute.to()
      // was indeed called by the handler.
      expect(
        () async => await handler.handle(uri),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Router not initialized'),
        )),
      );
    });
  });
}
