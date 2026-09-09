import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_deeplink/src/deeplink_manager.dart';
import 'package:magic_deeplink/src/exceptions/deeplink_exception.dart';
import 'package:magic_deeplink/src/drivers/app_links_driver.dart';
import 'package:magic_deeplink/src/drivers/deeplink_driver.dart';
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

/// A driver the provider can be handed in place of the real `AppLinksDriver`.
///
/// Two things make the real one untestable here. It answers `isSupported` from
/// the host platform, so a test built on it asserts one thing on a macOS
/// developer machine and the opposite on the Linux CI runner; and its link
/// stream comes straight out of the `app_links` package with no seam a test can
/// emit on. This one is told what to answer and owns its stream.
class FakeDeeplinkDriver extends DeeplinkDriver {
  /// Creates a driver that answers [isSupported] and was opened on [coldStart].
  FakeDeeplinkDriver({this.isSupported = true, this.coldStart});

  @override
  final bool isSupported;

  /// The link the application was opened on, or null for a warm start.
  ///
  /// Delivered the way `app_links` delivers it: on the stream as soon as
  /// somebody subscribes, AND from `getInitialLink()`. Both, independently,
  /// which is the whole of defect (c).
  final Uri? coldStart;

  /// The config maps `initialize` was called with, in order.
  final List<Map<String, dynamic>> initialized = [];

  /// How many times anything asked this driver for the initial link.
  int initialLinkCalls = 0;

  /// Whether the provider disposed this driver.
  bool isDisposed = false;

  late final StreamController<Uri> _links = StreamController<Uri>.broadcast(
    onListen: () {
      final Uri? uri = coldStart;

      if (uri != null) {
        _links.add(uri);
      }
    },
  );

  @override
  String get name => 'fake';

  @override
  Stream<Uri> get onLink => _links.stream;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    initialized.add(config);
  }

  @override
  Future<Uri?> getInitialLink() async {
    initialLinkCalls++;

    return coldStart;
  }

  /// Publishes a link that arrived while the application was already running.
  void emit(Uri uri) => _links.add(uri);

  /// Records the teardown, the way the real driver's own `dispose` behaves.
  ///
  /// `AppLinksDriver.dispose()` is empty because `app_links` owns its stream
  /// and needs no disposal, so closing the controller here would make the fake
  /// stricter than the thing it stands in for, and a test that emits after a
  /// provider teardown would hit the fake rather than the provider.
  @override
  void dispose() {
    isDisposed = true;
  }
}

/// Captures every URI the deeplink manager routes to it, and its provenance.
class CapturingHandler implements DeeplinkHandler {
  /// The URIs this handler was asked to handle, in order.
  final List<Uri> handled = [];

  /// Where each of those URIs came from, in the same order.
  final List<DeeplinkSource> sources = [];

  /// The payload each of those URIs arrived with, in the same order.
  final List<Map<String, dynamic>?> payloads = [];

  @override
  bool canHandle(Uri uri) => true;

  @override
  Future<bool> handle(
    Uri uri, {
    required DeeplinkSource source,
    Map<String, dynamic>? payload,
  }) async {
    handled.add(uri);
    sources.add(source);
    payloads.add(payload);

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

      // The manager is a singleton that outlives the container, and its driver,
      // its cached initial link and its link stream all survive a
      // `forgetHandlers()`. A test that asserts nothing was wired can only mean
      // it against a manager the previous test left empty.
      DeeplinkManager().reset();
    });

    tearDown(() {
      DeeplinkManager().reset();
    });

    test('register binds DeeplinkManager singleton', () {
      provider.register();
      expect(app.bound('deeplinks'), isTrue);
      expect(app.make('deeplinks'), isA<DeeplinkManager>());
    });

    test('boot wires nothing at all when deeplink.enabled is false', () async {
      await MagicApp.init(configs: [
        {
          'deeplink': {
            'enabled': false,
            'driver': 'app_links',
          }
        }
      ]);

      final notifications = FakeNotificationManager();

      await app.register(provider);
      await app.register(FakeNotificationServiceProvider(app, notifications));
      await app.boot();

      // The documented off switch. Nothing read it, so a consumer who turned
      // deep links off still got a driver, a link subscription and a push
      // bridge.
      final manager = app.make<DeeplinkManager>('deeplinks');
      expect(() => manager.driver, throwsA(isA<DeeplinkException>()));
      expect(notifications.hasClickListener, isFalse);

      await notifications.dispose();
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

      final driver = FakeDeeplinkDriver();
      provider = DeeplinkServiceProvider(app, driverFactory: () => driver);

      provider.register();
      await provider.boot();

      final manager = app.make<DeeplinkManager>('deeplinks');
      expect(manager.driver, same(driver));
    });

    test('boot never sets a driver the platform does not support', () async {
      await MagicApp.init(configs: [
        {
          'deeplink': {
            'enabled': true,
            'driver': 'app_links',
          }
        }
      ]);

      // What the web build gets. Nothing read `isSupported`, so a browser was
      // handed a driver whose stream is empty and whose initial link is always
      // null, and the manager answered `driver` with it.
      final driver = FakeDeeplinkDriver(isSupported: false);
      provider = DeeplinkServiceProvider(app, driverFactory: () => driver);

      provider.register();
      await provider.boot();

      final manager = app.make<DeeplinkManager>('deeplinks');
      expect(() => manager.driver, throwsA(isA<DeeplinkException>()));
      expect(driver.initialized, isEmpty);
    });

    test('boot defaults to the app_links driver', () async {
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

      // The consumer constructs `DeeplinkServiceProvider(app)` with no factory,
      // and what that produces is the platform arm of `AppLinksDriver`. The
      // gate above decides whether it is wired, so this is asserted on a host
      // that supports one and skipped where none exists; the gate ITSELF is
      // pinned platform-independently by the two tests above.
      final manager = app.make<DeeplinkManager>('deeplinks');
      expect(manager.driver, isA<AppLinksDriver>());
    },
        skip: AppLinksDriver().isSupported
            ? null
            : 'No app_links driver on this host, so there is nothing to wire.');

    test('boot hands the driver the whole deeplink config', () async {
      await MagicApp.init(configs: [
        {
          'deeplink': {
            'enabled': true,
            'driver': 'app_links',
            'scheme': 'https',
          }
        }
      ]);

      final driver = FakeDeeplinkDriver();
      provider = DeeplinkServiceProvider(app, driverFactory: () => driver);

      provider.register();
      await provider.boot();

      expect(driver.initialized, [
        {'enabled': true, 'driver': 'app_links', 'scheme': 'https'},
      ]);
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

      final driver = FakeDeeplinkDriver();
      provider = DeeplinkServiceProvider(app, driverFactory: () => driver);

      provider.register();
      await provider.boot();

      final manager = app.make<DeeplinkManager>('deeplinks');
      expect(manager.onLink, isA<Stream<Uri>>());
    });

    testWidgets(
        'a cold-start link served by both driver paths reaches the handler '
        'exactly once', (WidgetTester tester) async {
      await MagicApp.init(configs: [
        {
          'deeplink': {'enabled': true, 'driver': 'app_links'}
        }
      ]);

      final cold = Uri.parse('https://uptizm.com/incidents/42');
      final driver = FakeDeeplinkDriver(coldStart: cold);
      final handler = CapturingHandler();
      DeeplinkManager().registerHandler(handler);

      provider = DeeplinkServiceProvider(app, driverFactory: () => driver);
      await app.register(provider);
      await app.boot();

      // The link is delivered after the first frame, because that is when the
      // router the handler navigates through exists.
      await tester.pump();
      await tester.pump();

      // A COUNT, not a presence: the Android plugin serves one cold-start tap
      // through the stream and through `getInitialLink()` independently, and a
      // test that asserted only "the handler saw it" passed while the whole
      // chain ran twice.
      expect(handler.handled, [cold]);
      expect(handler.sources, [DeeplinkSource.osLink]);
      expect(handler.payloads, [null]);

      // The surviving path is the stream, the one `app_links` documents as
      // carrying the initial link and every later one.
      expect(driver.initialLinkCalls, 0);
    });

    testWidgets('a link that arrives while the app runs reaches the handler',
        (WidgetTester tester) async {
      await MagicApp.init(configs: [
        {
          'deeplink': {'enabled': true, 'driver': 'app_links'}
        }
      ]);

      final driver = FakeDeeplinkDriver();
      final handler = CapturingHandler();
      DeeplinkManager().registerHandler(handler);

      provider = DeeplinkServiceProvider(app, driverFactory: () => driver);
      await app.register(provider);
      await app.boot();
      await tester.pump();

      driver.emit(Uri.parse('https://uptizm.com/monitors/7'));
      await tester.pump();

      // Dropping the initial-link read must not cost the warm path: this is the
      // delivery the whole feature now rests on.
      expect(handler.handled, [Uri.parse('https://uptizm.com/monitors/7')]);
      expect(handler.sources, [DeeplinkSource.osLink]);
    });

    testWidgets(
        'routes a push click carrying deep_link when notifications is '
        'registered after this provider', (WidgetTester tester) async {
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

      // A push click waits for the first frame for the same reason an OS link
      // does: on a cold start it arrives before anything is drawn.
      await tester.pump();

      expect(handler.handled, [Uri.parse('https://uptizm.com/incidents/42')]);
      expect(handler.sources, [DeeplinkSource.push]);
      expect(handler.payloads, [
        {
          'deep_link': 'https://uptizm.com/incidents/42',
          'title': 'Monitor down',
        },
      ]);

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

      final driver = FakeDeeplinkDriver();
      provider = DeeplinkServiceProvider(app, driverFactory: () => driver);

      await app.register(provider);
      await app.boot();

      final manager = app.make<DeeplinkManager>('deeplinks');
      expect(manager.driver, same(driver));

      await provider.dispose();

      // `boot` calls `manager.setDriver(driver)` on the singleton, so clearing
      // only the provider's own field left `manager.driver` answering with a
      // driver this provider had just torn down, and `getInitialLink()` still
      // calling through it.
      //
      // `driver` raises rather than answering null when nothing is configured,
      // which is the honest state after a teardown: reaching for it is the
      // mistake, not the absence.
      expect(() => manager.driver, throwsA(isA<DeeplinkException>()));
      expect(driver.isDisposed, isTrue);
    });

    testWidgets('dispose drops a delivery that is waiting for the first frame',
        (WidgetTester tester) async {
      await MagicApp.init(configs: [
        {
          'deeplink': {'enabled': true, 'driver': 'app_links'}
        }
      ]);

      final driver = FakeDeeplinkDriver(
        coldStart: Uri.parse('https://uptizm.com/incidents/42'),
      );
      final handler = CapturingHandler();
      DeeplinkManager().registerHandler(handler);

      provider = DeeplinkServiceProvider(app, driverFactory: () => driver);
      await app.register(provider);
      await app.boot();

      // Microtasks only, deliberately: the link reaches the delivery and parks
      // there waiting for a frame that has not happened yet. That is the window
      // the `_disposed` check inside it exists for, and the only way to be in
      // it is to not pump. `idle` elapses zero fake time, which drains the
      // queue without ending a frame.
      await tester.idle();

      // Through `runAsync` because `dispose` awaits a stream cancellation whose
      // future completes in the ROOT zone, and awaiting that from inside this
      // test's fake-async zone hangs the test rather than failing it.
      await tester.runAsync(() => provider.dispose());

      await tester.pump();
      await tester.pump();

      expect(handler.handled, isEmpty);
    });

    testWidgets(
        'dispose stops the driver stream from routing anything afterwards',
        (WidgetTester tester) async {
      await MagicApp.init(configs: [
        {
          'deeplink': {'enabled': true, 'driver': 'app_links'}
        }
      ]);

      final driver = FakeDeeplinkDriver();
      final handler = CapturingHandler();
      DeeplinkManager().registerHandler(handler);

      provider = DeeplinkServiceProvider(app, driverFactory: () => driver);
      await app.register(provider);
      await app.boot();
      await tester.pump();

      // Through `runAsync` for the same reason as the test above: the stream
      // cancellation `dispose` awaits completes in the root zone.
      await tester.runAsync(() => provider.dispose());

      driver.emit(Uri.parse('https://uptizm.com/monitors/7'));
      await tester.pump();

      // Until this package had a driver seam, the cancellation could only be
      // read from the source: `AppLinksDriver` takes its stream straight from
      // `app_links` and a test could not emit on it.
      expect(handler.handled, isEmpty);
    });

    test('dispose completes on a driver-wired provider, and repeats safely',
        () async {
      await MagicApp.init(configs: [
        {
          'deeplink': {'enabled': true, 'driver': 'app_links'}
        }
      ]);

      provider = DeeplinkServiceProvider(
        app,
        driverFactory: FakeDeeplinkDriver.new,
      );

      await app.register(provider);
      await app.boot();

      // `doc/basics/handlers.md` tells a consumer to call teardown from their
      // service provider, and a consumer does not know which parts this
      // deployment wired, so calling it on a provider with a driver but no
      // notifications, and calling it twice, both have to be safe.
      await provider.dispose();
      await provider.dispose();
    }, timeout: const Timeout(Duration(seconds: 10)));

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
