import 'package:flutter_test/flutter_test.dart';
import 'package:magic_deeplink/src/handlers/deeplink_handler.dart';
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

    group('with hosts set', () {
      late RouteDeeplinkHandler gatedHandler;

      setUp(() {
        gatedHandler = RouteDeeplinkHandler(
          paths: ['/monitors/:id'],
          hosts: ['example.com'],
        );
      });

      test('accepts a relative URI (push payload path)', () {
        expect(gatedHandler.canHandle(Uri.parse('/monitors/5')), isTrue);
      });

      test('accepts an absolute URI matching a host case-insensitively', () {
        expect(
          gatedHandler.canHandle(Uri.parse('https://EXAMPLE.com/monitors/5')),
          isTrue,
        );
      });

      test('rejects an absolute URI on a different host', () {
        expect(
          gatedHandler.canHandle(Uri.parse('https://evil.com/monitors/5')),
          isFalse,
        );
      });

      test('rejects an absolute URI carrying an explicit port', () {
        expect(
          gatedHandler
              .canHandle(Uri.parse('https://example.com:8443/monitors/5')),
          isFalse,
        );
      });

      test('rejects an absolute URI carrying userinfo', () {
        expect(
          gatedHandler.canHandle(Uri.parse('https://a@example.com/monitors/5')),
          isFalse,
        );
      });

      test('rejects a non-http(s) scheme', () {
        expect(
          gatedHandler.canHandle(Uri.parse('ftp://example.com/monitors/5')),
          isFalse,
        );
      });
    });

    group('with hosts containing only blank entries', () {
      late RouteDeeplinkHandler blankHostsHandler;

      setUp(() {
        blankHostsHandler = RouteDeeplinkHandler(
          paths: ['/monitors/:id'],
          hosts: [''],
        );
      });

      test('rejects an absolute URI with an empty host', () {
        expect(
          blankHostsHandler.canHandle(Uri.parse('https:/monitors/5')),
          isFalse,
        );
      });

      test('rejects an absolute URI on a real host', () {
        expect(
          blankHostsHandler
              .canHandle(Uri.parse('https://other-app.example/monitors/5')),
          isFalse,
        );
      });

      test('still accepts a relative URI', () {
        expect(blankHostsHandler.canHandle(Uri.parse('/monitors/5')), isTrue);
      });
    });

    test('without hosts, an absolute URI on any host still matches', () {
      expect(
        handler.canHandle(Uri.parse('https://evil.com/monitors/5')),
        isTrue,
      );
    });

    group('caseSensitive', () {
      test('default (case-insensitive) still matches an uppercased path', () {
        expect(
          handler.canHandle(Uri.parse('https://example.com/MONITORS/5')),
          isTrue,
        );
      });

      test('caseSensitive: true matches the exact case', () {
        final strictHandler = RouteDeeplinkHandler(
          paths: ['/monitors/:id'],
          caseSensitive: true,
        );

        expect(
          strictHandler.canHandle(Uri.parse('https://example.com/monitors/5')),
          isTrue,
        );
        expect(
          strictHandler.canHandle(Uri.parse('https://example.com/MONITORS/5')),
          isFalse,
        );
      });
    });

    test('handle attempts to navigate via MagicRoute', () async {
      final uri = Uri.parse('https://example.com/some/path');
      // Since MagicRouter is not initialized in this unit test environment,
      // it throws a StateError. Catching this error confirms that MagicRoute.to()
      // was indeed called by the handler.
      expect(
        () async => await handler.handle(uri, source: DeeplinkSource.osLink),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Router not initialized'),
        )),
      );
    });
  });
}
