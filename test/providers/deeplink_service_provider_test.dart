import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_deeplink/src/deeplink_manager.dart';
import 'package:magic_deeplink/src/exceptions/deeplink_exception.dart';
import 'package:magic_deeplink/src/drivers/app_links_driver.dart';
import 'package:magic_deeplink/src/handlers/deeplink_handler.dart';
import 'package:magic_deeplink/src/providers/deeplink_service_provider.dart';

/// A push click event shaped like `magic_notifications`' `PushNotificationEvent`.
///
/// Deliberately NOT a `Map<String, dynamic>`: the payload lives behind a `data`
/// field on an event object, which is the shape the real stream publishes and
/// the shape the old wiring cast away.
class FakePushNotificationEvent {
  /// The notification payload, carrying the server's own keys flat.
  final Map<String, dynamic> data;

  /// Creates an event carrying [data].
  const FakePushNotificationEvent(this.data);
}

/// Stands in for `magic_notifications`' `NotificationManager`.
///
/// It publishes clicks the way the real manager does: `onPushClicked` is a
/// broadcast stream that exists from construction, while `pushDriver` only
/// answers once the notifications provider has booted and attached one.
class FakeNotificationManager {
  final StreamController<FakePushNotificationEvent> _clicks =
      StreamController<FakePushNotificationEvent>.broadcast();

  bool _driverAttached = false;

  /// Whether anything is subscribed to the click stream.
  bool get hasClickListener => _clicks.hasListener;

  /// Push notifications the user tapped.
  Stream<FakePushNotificationEvent> get onPushClicked => _clicks.stream;

  /// The attached push driver, which does not exist before boot.
  Object get pushDriver {
    if (!_driverAttached) {
      throw StateError('Push driver not configured.');
    }

    return _driverAttached;
  }

  /// Attaches the driver, as the notifications provider's `boot` does.
  void attachDriver() => _driverAttached = true;

  /// Publishes a tapped push carrying [data].
  void publishClick(Map<String, dynamic> data) {
    if (!_driverAttached) {
      throw StateError('No driver is attached, so no push can arrive.');
    }

    _clicks.add(FakePushNotificationEvent(data));
  }

  /// Closes the click stream.
  Future<void> dispose() => _clicks.close();
}

/// A notifications manager that publishes nothing a deeplink can be read from.
class FakeShapelessNotificationManager {
  /// The one thing this build offers, and not the click stream.
  String get name => 'shapeless';
}

/// A manager whose click-stream getter throws something the handler does not
/// answer.
///
/// `NoSuchMethodError` means "this build is too old" and the handler reports it
/// by name. A `StateError` means something else entirely, and it is what an
/// uninitialised manager throws; unguarded, it escapes `boot()` and aborts the
/// whole application.
class FakeThrowingNotificationManager {
  /// Throws rather than answering, as an uninitialised manager does.
  Stream<Object> get onPushClicked =>
      throw StateError('NotificationManager is not initialised.');
}

/// Binds a `notifications` factory that throws when it is resolved.
///
/// `app.make` runs the binding factory, so a misconfigured notifications plugin
/// can fail at RESOLUTION rather than at construction, before the deeplink
/// provider ever reaches the manager.
class FakeThrowingNotificationServiceProvider extends ServiceProvider {
  /// Creates the provider whose `notifications` factory throws.
  FakeThrowingNotificationServiceProvider(super.app);

  @override
  void register() {
    app.singleton('notifications', () {
      throw StateError('The notifications plugin is misconfigured.');
    });
  }
}

/// Registers notifications the way `NotificationServiceProvider` does.
///
/// The manager is bound in `register`, so it is resolvable before any provider
/// boots; the driver is only attached in `boot`, which runs AFTER the deeplink
/// provider's when notifications is registered second.
class FakeNotificationServiceProvider extends ServiceProvider {
  /// The manager this provider binds.
  final Object manager;

  /// Creates the provider binding [manager] under `notifications`.
  FakeNotificationServiceProvider(super.app, this.manager);

  @override
  void register() {
    app.singleton('notifications', () => manager);
  }

  @override
  Future<void> boot() async {
    if (manager is FakeNotificationManager) {
      (manager as FakeNotificationManager).attachDriver();
    }
  }
}

/// Captures every URI the deeplink manager routes to it.
class CapturingHandler implements DeeplinkHandler {
  /// The URIs this handler was asked to handle, in order.
  final List<Uri> handled = [];

  @override
  bool canHandle(Uri uri) => true;

  @override
  Future<bool> handle(Uri uri) async {
    handled.add(uri);

    return true;
  }
}

void main() {
  group('DeeplinkServiceProvider', () {
    late MagicApp app;
    late DeeplinkServiceProvider provider;

    setUp(() {
      MagicApp.reset();
      app = MagicApp.instance;
      provider = DeeplinkServiceProvider(app);
      DeeplinkManager().forgetHandlers();
    });

    tearDown(() {
      DeeplinkManager().forgetHandlers();
    });

    test('register binds DeeplinkManager singleton', () {
      provider.register();
      expect(app.bound('deeplinks'), isTrue);
      expect(app.make('deeplinks'), isA<DeeplinkManager>());
    });

    test('boot sets driver when configured', () async {
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
        'routes a push click carrying deep_link when notifications is '
        'registered after this provider', () async {
      await MagicApp.init(configs: [
        {
          'deeplink': {'enabled': true}
        }
      ]);

      final notifications = FakeNotificationManager();
      final handler = CapturingHandler();
      DeeplinkManager().registerHandler(handler);

      // The consumer's own order: deeplinks first, notifications second, so the
      // push driver does not exist while this provider boots.
      await app.register(provider);
      await app.register(FakeNotificationServiceProvider(app, notifications));
      await app.boot();

      notifications.publishClick({
        'deep_link': 'https://uptizm.com/incidents/42',
        'title': 'Monitor down',
      });
      await Future<void>.delayed(Duration.zero);

      expect(handler.handled, [Uri.parse('https://uptizm.com/incidents/42')]);

      await notifications.dispose();
    });

    test('dispose stops routing pushes the provider had wired', () async {
      await MagicApp.init(configs: [
        {
          'deeplink': {'enabled': true}
        }
      ]);

      final notifications = FakeNotificationManager();
      final handler = CapturingHandler();
      DeeplinkManager().registerHandler(handler);

      await app.register(provider);
      await app.register(FakeNotificationServiceProvider(app, notifications));
      await app.boot();

      await provider.dispose();

      notifications.publishClick({
        'deep_link': 'https://uptizm.com/incidents/42',
      });
      await Future<void>.delayed(Duration.zero);

      expect(handler.handled, isEmpty);

      await notifications.dispose();
    });

    test('dispose drops the manager\'s driver, not only the provider\'s field',
        () async {
      await MagicApp.init(configs: [
        {
          'deeplink': {'enabled': true, 'driver': 'app_links'}
        }
      ]);

      await app.register(provider);
      await app.boot();

      final manager = app.make<DeeplinkManager>('deeplinks');
      expect(manager.driver, isA<AppLinksDriver>());

      await provider.dispose();

      // `boot` calls `manager.setDriver(driver)` on the singleton, so clearing
      // only the provider's own field left `manager.driver` answering with a
      // driver this provider had just torn down, and `getInitialLink()` still
      // calling through it. Harmless only while `AppLinksDriver.dispose()` is
      // an empty method.
      //
      // `driver` raises rather than answering null when nothing is configured,
      // which is the honest state after a teardown: reaching for it is the
      // mistake, not the absence.
      expect(() => manager.driver, throwsA(isA<DeeplinkException>()));
    });

    // The `_disposed` checks around the scheduled initial-link read are NOT
    // independently covered, and a test that looked like it covered them would
    // be worse than this comment. One was written and then deleted: it stayed
    // green against a build with both checks removed, because `dispose()` also
    // calls `manager.forgetDriver()`, so the callback's `getInitialLink()`
    // raises "no driver configured" into a fire-and-forget future that swallows
    // it, and `handler.handled` is empty either way.
    //
    // Isolating the checks needs a `getInitialLink()` that actually answers a
    // URI, which needs a driver seam `AppLinksDriver` does not have. The checks
    // stay because relying on that throw IS the swallowed-error shape this
    // package spent this release removing: an early return is the deliberate
    // version of the same outcome.

    test('dispose completes on a driver-wired provider, and repeats safely',
        () async {
      await MagicApp.init(configs: [
        {
          'deeplink': {'enabled': true, 'driver': 'app_links'}
        }
      ]);

      await app.register(provider);
      await app.boot();

      // `doc/basics/handlers.md` tells a consumer to call teardown from their
      // service provider, and a consumer does not know which parts this
      // deployment wired, so calling it on a provider with a driver but no
      // notifications, and calling it twice, both have to be safe.
      await provider.dispose();
      await provider.dispose();
    }, timeout: const Timeout(Duration(seconds: 10)));

    // NOT covered here, and worth saying so rather than implying otherwise:
    // that the driver's link subscription stops delivering. `AppLinksDriver`
    // exposes `_appLinks.uriLinkStream` straight from the `app_links` package
    // with no injection seam, so a unit test cannot emit on it. What the test
    // above pins is that dispose reaches the driver path at all and is
    // idempotent; the cancellation itself is read from the source.

    test(
        'a notifications factory that throws is reported and does not abort '
        'app boot', () async {
      await MagicApp.init(configs: [
        {
          'deeplink': {'enabled': true}
        }
      ]);

      final log = Log.fake();

      await app.register(provider);
      await app.register(FakeThrowingNotificationServiceProvider(app));

      // The assertion that matters is that this completes at all. magic's
      // `Application.boot` awaits providers in a bare loop, so an escaping
      // throw here would abort boot and every provider after this one.
      await app.boot();

      expect(app.isBooted, isTrue);
      expect(
        log.entries.where(
          (entry) =>
              entry.level == 'error' && entry.message.contains('misconfigured'),
        ),
        isNotEmpty,
      );
    });

    test(
        'an onPushClicked getter that throws a StateError is reported and does '
        'not abort app boot', () async {
      await MagicApp.init(configs: [
        {
          'deeplink': {'enabled': true}
        }
      ]);

      final log = Log.fake();

      await app.register(provider);
      await app.register(
        FakeNotificationServiceProvider(
          app,
          FakeThrowingNotificationManager(),
        ),
      );

      await app.boot();

      expect(app.isBooted, isTrue);
      expect(
        log.entries.where(
          (entry) =>
              entry.level == 'error' &&
              entry.message.contains('not initialised'),
        ),
        isNotEmpty,
      );
    });

    test('subscribes to nothing when notifications is not installed', () async {
      await MagicApp.init(configs: [
        {
          'deeplink': {'enabled': true}
        }
      ]);

      final notifications = FakeNotificationManager();

      await app.register(provider);
      await app.boot();

      expect(app.bound('notifications'), isFalse);
      expect(notifications.hasClickListener, isFalse);

      await notifications.dispose();
    });

    test('reports when the bound notifications manager publishes no clicks',
        () async {
      await MagicApp.init(configs: [
        {
          'deeplink': {'enabled': true}
        }
      ]);

      final log = Log.fake();

      await app.register(provider);
      await app.register(
        FakeNotificationServiceProvider(
            app, FakeShapelessNotificationManager()),
      );
      await app.boot();

      expect(
        log.entries.where(
          (entry) =>
              entry.level == 'error' && entry.message.contains('onPushClicked'),
        ),
        isNotEmpty,
      );
    });
  });
}
