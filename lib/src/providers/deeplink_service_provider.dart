import 'dart:async';

import 'package:magic/magic.dart';
import '../deeplink_manager.dart';
import '../drivers/app_links_driver.dart';
import '../handlers/onesignal_deeplink_handler.dart';

class DeeplinkServiceProvider extends ServiceProvider {
  DeeplinkServiceProvider(super.app);

  /// The push-click handler this provider wired, when it wired one.
  ///
  /// Held rather than discarded so [dispose] can reach it. `doc/basics/handlers.md`
  /// tells a consumer to tear handlers down from their provider, and a handler
  /// constructed inline in [boot] makes that instruction impossible to follow.
  OneSignalDeeplinkHandler? _pushClicks;

  /// The driver's link stream, held for the same reason as [_pushClicks].
  StreamSubscription<Uri>? _links;

  /// The driver this provider created, when it created one.
  AppLinksDriver? _driver;

  @override
  void register() {
    app.singleton('deeplinks', () => DeeplinkManager());
  }

  /// Tear down everything this provider wired.
  ///
  /// Provider-level, not handler-level. `doc/basics/handlers.md` tells a
  /// consumer to call teardown from their service provider, so a `dispose()`
  /// here that reached only the push-click handler would read as tearing the
  /// provider down while leaving the driver's own link subscription and the
  /// driver itself running. Everything [boot] created is dropped, and the
  /// method is idempotent so a consumer may call it without knowing which parts
  /// this deployment actually wired.
  Future<void> dispose() async {
    _pushClicks?.dispose();
    _pushClicks = null;

    await _links?.cancel();
    _links = null;

    _driver?.dispose();
    _driver = null;
  }

  @override
  Future<void> boot() async {
    final config = app.make<ConfigRepository>('config');
    final driverName = config.get('deeplink.driver');
    final manager = app.make<DeeplinkManager>('deeplinks');

    if (driverName == 'app_links') {
      final driver = AppLinksDriver();
      _driver = driver;
      manager.setDriver(driver);
      await driver.initialize(config.get('deeplink') ?? {});

      // Connect driver stream to manager
      _links = driver.onLink.listen((uri) {
        manager.handleUri(uri);
      });

      // Handle initial link - delay to ensure router is ready
      // Router is initialized after runApp() completes, so we wait for the first frame
      Future.delayed(Duration.zero, () async {
        final uri = await manager.getInitialLink();
        if (uri != null) {
          manager.handleUri(uri);
        }
      });
    }

    // Route tapped push notifications, when the consumer installed the
    // notifications plugin. An app that ships deep links without push is the
    // normal case and nothing at all is created for it here, so there is no
    // subscription and no timer to leak.
    //
    // Only the BINDING is required at this point, never the push driver: every
    // provider has registered by the time any of them boots, so the manager is
    // resolvable here even though the notifications provider boots after this
    // one and attaches its driver there. The handler subscribes to the
    // manager's own click stream, which exists from construction and carries
    // whatever a driver attached later publishes.
    //
    // Guarded because this runs inside `boot()`, and magic's `Application.boot`
    // awaits providers in a bare loop with no error handling of its own
    // (`foundation/application.dart:375`). An unguarded throw here therefore
    // does not fail the deep-link feature, it aborts app boot and every
    // provider registered after this one. A notifications binding whose factory
    // throws, or a manager whose `onPushClicked` getter throws anything other
    // than the `NoSuchMethodError` the handler already answers (a `StateError`
    // out of an uninitialised manager, say), would take the whole app down over
    // an OPTIONAL plugin.
    //
    // This is not the empty catch this wiring replaced. That one had two
    // comment lines for a body and is why the feature stayed inert across two
    // years of releases; this one reports at error level through the same seam
    // every other failure here uses, and only then lets boot continue.
    if (app.bound('notifications')) {
      final handler = OneSignalDeeplinkHandler();

      try {
        handler.setup(manager, app.make('notifications'));
        _pushClicks = handler;
      } catch (error) {
        handler.dispose();

        if (Magic.bound('log')) {
          Log.error(
            '[deeplink] Resolving the bound `notifications` manager failed, so '
            'a tapped push notification cannot open a deep link: $error',
          );
        }
      }
    }
  }
}
