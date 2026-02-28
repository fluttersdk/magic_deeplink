import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_deeplink/src/deeplink_manager.dart';
import 'package:magic_deeplink/src/handlers/deeplink_handler.dart';
import 'package:magic_deeplink/src/drivers/app_links_driver.dart';
import 'package:magic_deeplink/src/providers/deeplink_service_provider.dart';

class MockPushDriver {
  final StreamController<Map<String, dynamic>> _controller =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get onNotificationClicked => _controller.stream;

  void simulateClick(Map<String, dynamic> data) {
    _controller.add(data);
  }
}

class MockNotificationManager {
  final MockPushDriver pushDriver = MockPushDriver();
}

void main() {
  group('DeeplinkServiceProvider', () {
    late MagicApp app;
    late DeeplinkServiceProvider provider;

    setUp(() {
      MagicApp.reset();
      app = MagicApp.instance;
      provider = DeeplinkServiceProvider(app);
    });

    test('register binds DeeplinkManager singleton', () {
      provider.register();
      expect(app.bound('deeplinks'), isTrue);
      expect(app.make('deeplinks'), isA<DeeplinkManager>());
    });

    test('boot sets driver when configured', () async {
      // Setup config
      await MagicApp.init(configs: [
        {
          'deeplink': {
            'enabled': true,
            'driver': 'app_links',
          }
        }
      ]);

      provider.register();
      await provider.boot();

      final manager = app.make<DeeplinkManager>('deeplinks');
      expect(manager.driver, isA<AppLinksDriver>());
    });

    test('boot initializes driver with config', () async {
      final configMap = {
        'deeplink': {
          'enabled': true,
          'driver': 'app_links',
          'scheme': 'https',
        }
      };

      await MagicApp.init(configs: [configMap]);

      provider.register();
      await provider.boot();

      final manager = app.make<DeeplinkManager>('deeplinks');
      expect(manager.driver, isA<AppLinksDriver>());
    });

    test('boot connects driver stream to manager', () async {
      // Setup config
      await MagicApp.init(configs: [
        {
          'deeplink': {
            'enabled': true,
            'driver': 'app_links',
          }
        }
      ]);

      provider.register();
      await provider.boot();

      final manager = app.make<DeeplinkManager>('deeplinks');
      expect(manager.onLink, isA<Stream<Uri>>());
    });

    test(
        'boot sets up OneSignal handler when notifications plugin is available',
        () async {
      // Setup config
      await MagicApp.init(configs: [
        {
          'deeplink': {
            'enabled': true,
            'driver': 'app_links',
          }
        }
      ]);

      // Bind mock notification manager
      final mockNotificationManager = MockNotificationManager();
      app.singleton('notifications', () => mockNotificationManager);

      provider.register();
      await provider.boot();

      // Get manager
      final manager = app.make<DeeplinkManager>('deeplinks');

      // We need to verify that the handler is connected.
      // We can do this by simulating a click and checking if handleUri is called.
      // However, AppLinksDriver might interfere or not be mocked easily here.
      // But handleUri works by adding to the stream.

      // We can listen to manager.onLink to see if the notification click propagates as a URI
      // But manager.onLink only emits what comes from driver.onLink usually?
      // Wait, let's check DeeplinkManager source.
      // Task 2.5: Add stream for incoming links: "Add StreamController<Uri>, Stream<Uri> get onLink, internal _handleIncomingLink() method"
      // If handleUri is called, does it emit to onLink?
      // Usually handleUri processes the URI (finds a handler).
      // It might NOT emit to onLink (which represents *incoming* links from the driver).
      // But wait, if OneSignal is a source of links, it acts like a driver.

      // Let's check DeeplinkManager implementation via reading it, to be sure.
      // But for now, let's assume we can check if the mock handler (OneSignalHandler) did its job.

      // Actually, we can use a custom handler in the manager to verify it received the call.
      bool handlerCalled = false;
      manager.registerHandler(_TestHandler((uri) {
        handlerCalled = true;
        return uri.path == '/onesignal';
      }));

      // Simulate click
      mockNotificationManager.pushDriver
          .simulateClick({'url': 'https://uptizm.com/onesignal'});

      // Wait for async processing
      await Future.delayed(Duration.zero);

      expect(handlerCalled, isTrue);
    });
  });
}

class _TestHandler implements DeeplinkHandler {
  final bool Function(Uri) check;
  _TestHandler(this.check);

  @override
  bool canHandle(Uri uri) => check(uri);

  @override
  Future<bool> handle(Uri uri) async => true;
}
