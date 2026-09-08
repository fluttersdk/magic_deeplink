import 'package:flutter_test/flutter_test.dart';
import 'package:magic_deeplink/src/deeplink_manager.dart';
import 'package:magic_deeplink/src/handlers/deeplink_handler.dart';
import 'package:magic_deeplink/src/exceptions/deeplink_exception.dart';
import 'package:magic_deeplink/src/drivers/deeplink_driver.dart';

class MockDeeplinkHandler extends DeeplinkHandler {
  final bool canHandleValue;
  final bool handleValue;
  bool handleCalled = false;

  /// The provenance the last call arrived with.
  DeeplinkSource? handledSource;

  /// The payload the last call arrived with.
  Map<String, dynamic>? handledPayload;

  MockDeeplinkHandler({this.canHandleValue = true, this.handleValue = true});

  @override
  bool canHandle(Uri uri) => canHandleValue;

  @override
  Future<bool> handle(
    Uri uri, {
    required DeeplinkSource source,
    Map<String, dynamic>? payload,
  }) async {
    handleCalled = true;
    handledSource = source;
    handledPayload = payload;

    return handleValue;
  }
}

class MockDeeplinkDriver extends DeeplinkDriver {
  final Uri? initialLink;

  /// How many times the manager reached through to the driver for it.
  int initialLinkCalls = 0;

  MockDeeplinkDriver({this.initialLink});

  @override
  String get name => 'mock';

  @override
  bool get isSupported => true;

  @override
  Stream<Uri> get onLink => const Stream.empty();

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}

  @override
  Future<Uri?> getInitialLink() async {
    initialLinkCalls++;

    return initialLink;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('DeeplinkManager', () {
    late DeeplinkManager manager;

    setUp(() {
      manager = DeeplinkManager();
      manager.reset();
    });

    test('is a singleton', () {
      final instance1 = DeeplinkManager();
      final instance2 = DeeplinkManager();
      expect(identical(instance1, instance2), isTrue);
    });

    test('registerHandler adds handler to list', () {
      final handler = MockDeeplinkHandler();
      manager.registerHandler(handler);
      expect(manager.hasHandler(handler), isTrue);
    });

    test('forgetHandlers clears all handlers', () {
      final handler = MockDeeplinkHandler();
      manager.registerHandler(handler);
      manager.forgetHandlers();
      expect(manager.hasHandler(handler), isFalse);
    });

    test('driver getter throws when not configured', () {
      expect(() => manager.driver, throwsA(isA<DeeplinkException>()));
    });

    test('setDriver sets the driver', () {
      final driver = MockDeeplinkDriver();
      manager.setDriver(driver);
      expect(manager.driver, equals(driver));
    });

    test('forgetDriver clears the driver', () {
      final driver = MockDeeplinkDriver();
      manager.setDriver(driver);
      manager.forgetDriver();
      expect(() => manager.driver, throwsA(isA<DeeplinkException>()));
    });

    test('handleUri calls first matching handler', () async {
      final handler1 = MockDeeplinkHandler(canHandleValue: false);
      final handler2 =
          MockDeeplinkHandler(canHandleValue: true, handleValue: true);
      final handler3 =
          MockDeeplinkHandler(canHandleValue: true, handleValue: false);

      manager.registerHandler(handler1);
      manager.registerHandler(handler2);
      manager.registerHandler(handler3);

      final result = await manager.handleUri(
        Uri.parse('https://example.com'),
        source: DeeplinkSource.osLink,
      );

      expect(result, isTrue);
      expect(handler1.handleCalled, isFalse);
      expect(handler2.handleCalled, isTrue);
      expect(handler3.handleCalled, isFalse);
    });

    test('handleUri hands the handler the provenance and the payload',
        () async {
      final handler = MockDeeplinkHandler();
      manager.registerHandler(handler);

      await manager.handleUri(
        Uri.parse('https://uptizm.com/incidents/1'),
        source: DeeplinkSource.push,
        payload: {'deep_link': '/incidents/1', 'team_id': 't-9'},
      );

      expect(handler.handledSource, DeeplinkSource.push);
      expect(
        handler.handledPayload,
        {'deep_link': '/incidents/1', 'team_id': 't-9'},
      );
    });

    test('handleUri returns false if no handler matches', () async {
      final handler = MockDeeplinkHandler(canHandleValue: false);
      manager.registerHandler(handler);

      final result = await manager.handleUri(
        Uri.parse('https://example.com'),
        source: DeeplinkSource.osLink,
      );

      expect(result, isFalse);
      expect(handler.handleCalled, isFalse);
    });

    test('onLink stream emits handled URIs', () async {
      final uri = Uri.parse('https://example.com');

      expectLater(manager.onLink, emits(uri));

      await manager.handleUri(uri, source: DeeplinkSource.manual);
    });

    test('getInitialLink returns initial link from driver', () async {
      final uri = Uri.parse('https://example.com');
      final driver = MockDeeplinkDriver(initialLink: uri);
      manager.setDriver(driver);

      final result = await manager.getInitialLink();

      expect(result, equals(uri));
    });

    test('getInitialLink caches result', () async {
      final uri = Uri.parse('https://example.com');
      final driver = MockDeeplinkDriver(initialLink: uri);
      manager.setDriver(driver);

      await manager.getInitialLink();
      await manager.getInitialLink();

      expect(await manager.getInitialLink(), equals(uri));
      expect(driver.initialLinkCalls, 1);
    });

    test('reset drops the cached initial link the singleton would keep',
        () async {
      final driver = MockDeeplinkDriver(
        initialLink: Uri.parse('https://example.com'),
      );
      manager.setDriver(driver);
      await manager.getInitialLink();

      // `forgetDriver` alone leaves the cache behind, so the next application
      // built in the same test binary answers with the previous one's link and
      // never reaches its own driver.
      manager.reset();

      final second = MockDeeplinkDriver(
        initialLink: Uri.parse('https://uptizm.com/incidents/1'),
      );
      manager.setDriver(second);

      expect(
        await manager.getInitialLink(),
        Uri.parse('https://uptizm.com/incidents/1'),
      );
      expect(second.initialLinkCalls, 1);
    });

    test('reset closes the link stream and opens a fresh one', () async {
      final closed = manager.onLink;

      expectLater(closed, emitsDone);
      manager.reset();

      // The controller is a broadcast one nothing ever closed, so a listener
      // from a torn-down application kept receiving links from the next.
      expectLater(manager.onLink, emits(Uri.parse('https://example.com')));

      await manager.handleUri(
        Uri.parse('https://example.com'),
        source: DeeplinkSource.manual,
      );
    });
  });
}
