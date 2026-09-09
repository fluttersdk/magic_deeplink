import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import '../deeplink_manager.dart';
import '../drivers/app_links_driver.dart';
import '../drivers/deeplink_driver.dart';
import '../handlers/deeplink_handler.dart';
import '../handlers/onesignal_deeplink_handler.dart';

/// Wires deep linking into a magic application.
///
/// Binds the [DeeplinkManager] singleton in [register], and in [boot] reads
/// `deeplink.enabled`, creates the platform driver when the platform has one,
/// and routes both the link the app was opened on and every link that arrives
/// afterwards through the manager. Push clicks are bridged in as well when the
/// consumer installed `magic_notifications`.
class DeeplinkServiceProvider extends ServiceProvider {
  /// Creates the provider.
  ///
  /// [driverFactory] builds the driver [boot] wires, and defaults to the
  /// platform arm of [AppLinksDriver], which is what a consumer wants. A test
  /// passes its own because the real driver answers `isSupported` from the host
  /// platform and takes its link stream straight from the `app_links` package,
  /// so neither the gate below nor the delivery path can be exercised through
  /// it.
  DeeplinkServiceProvider(super.app, {DeeplinkDriver Function()? driverFactory})
      : _driverFactory = driverFactory ?? AppLinksDriver.new;

  /// Builds the driver [boot] wires.
  final DeeplinkDriver Function() _driverFactory;

  /// The push-click handler this provider wired, when it wired one.
  ///
  /// Held rather than discarded so [dispose] can reach it. `doc/basics/handlers.md`
  /// tells a consumer to tear handlers down from their provider, and a handler
  /// constructed inline in [boot] makes that instruction impossible to follow.
  OneSignalDeeplinkHandler? _pushClicks;

  /// The driver's link stream, held for the same reason as [_pushClicks].
  StreamSubscription<Uri>? _links;

  /// The driver this provider created, when it created one.
  DeeplinkDriver? _driver;

  /// Whether [dispose] has run since the last [boot].
  ///
  /// A delivery that is already waiting for the first frame cannot be
  /// cancelled, and neither can a `boot` suspended inside `driver.initialize`,
  /// so a `dispose()` in either window would otherwise be followed by the work
  /// it was supposed to stop. The flag is what those points check instead.
  bool _disposed = false;

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
    _disposed = true;

    _pushClicks?.dispose();
    _pushClicks = null;

    await _links?.cancel();
    _links = null;

    if (_driver != null) {
      _driver!.dispose();
      _driver = null;

      // The manager holds its OWN reference, set by `boot`, and dropping only
      // this field left the singleton answering `manager.driver` with a driver
      // this provider had just torn down, with `getInitialLink()` still calling
      // through it. Harmless only while `AppLinksDriver.dispose()` is an empty
      // method, which is not a property to depend on.
      app.make<DeeplinkManager>('deeplinks').forgetDriver();
    }
  }

  /// Hand [uri] to [manager], once [firstFrame] says the router exists.
  ///
  /// [MagicRoute.to] throws a `StateError` until `MagicApp` builds the router,
  /// which it does while the first frame is being built, and a link that
  /// arrives before that is the ordinary cold start rather than an edge case.
  /// The wait this replaced was a zero-duration timer, which is a guess about
  /// how long a boot takes and loses the link on any boot slower than it; the
  /// end of a frame is the event itself. It is also strictly more than a
  /// post-frame callback: `endOfFrame` SCHEDULES the frame when the scheduler
  /// is idle, so a link handed to an application nobody is drawing still gets
  /// delivered rather than waiting for a frame that never comes.
  ///
  /// Known gap, raised in review and NOT closed here because settling it needs
  /// a device rather than an argument. The end of a frame is not literally the
  /// same event as "the router exists": magic builds it at
  /// `foundation/magic.dart:112`, AFTER the `await boot()` on the line above,
  /// so throughout every provider's boot `MagicRouter._router` is still null
  /// and `MagicRoute.to` would throw. This future is captured during that boot
  /// and a cold-start link queues behind it immediately, since `app_links`
  /// replays the launch link on first listen. If a provider registered after
  /// this one yields the event loop in its own boot, and the scheduler serves
  /// the frame inside that window, delivery resumes against a null router. The
  /// `try`/`catch` below turns that into a logged error rather than a silent
  /// loss, which is why this is a gap rather than a regression, and the path
  /// was measured working on a physical iPhone. If a cold-start link is ever
  /// reported lost WITH a `StateError` in the log, this paragraph is the
  /// place to start.
  ///
  /// Nothing awaits this future, so it swallows nothing and lets nothing
  /// escape: an error here reaches no caller, and left alone it would surface
  /// as an unhandled async error and take a tapped link with it.
  Future<void> _deliver(
    DeeplinkManager manager,
    Uri uri,
    Future<void> firstFrame,
  ) async {
    try {
      await firstFrame;

      // A teardown that landed while the frame was pending. The subscription is
      // cancelled by then, but this delivery was already in flight.
      if (_disposed) {
        return;
      }

      await manager.handleUri(uri, source: DeeplinkSource.osLink);
    } catch (error) {
      if (Magic.bound('log')) {
        Log.error(
          '[deeplink] Routing an incoming deep link failed, so the app did not '
          'open $uri: $error',
        );
      }
    }
  }

  @override
  Future<void> boot() async {
    _disposed = false;

    final ConfigRepository config = app.make<ConfigRepository>('config');
    final String? driverName = config.get<String>('deeplink.driver');
    final DeeplinkManager manager = app.make<DeeplinkManager>('deeplinks');

    // The documented off switch, and until now nothing read it: a consumer who
    // set it still got a driver, a link subscription and a push bridge. An
    // absent key means on, which is what `doc/getting-started/configuration.md`
    // tells a consumer (`Config.get<bool>('deeplink.enabled', true)`), and only
    // an explicit false wires nothing.
    if (config.get<bool>('deeplink.enabled') == false) {
      return;
    }

    final DeeplinkDriver? driver =
        driverName == 'app_links' ? _driverFactory() : null;

    // A driver that says it cannot serve this platform is not initialised, not
    // handed to the manager and not subscribed to: the web arm answers false
    // and has an empty stream and a null initial link behind it, so wiring it
    // would leave `manager.driver` answering with something that can never
    // deliver, and every browser build carrying a driver for a mechanism the
    // browser does not have.
    if (driver != null && driver.isSupported) {
      _driver = driver;
      manager.setDriver(driver);
      await driver.initialize(
        config.get<Map<String, dynamic>>('deeplink') ?? <String, dynamic>{},
      );

      // A teardown that landed inside that await already cleared `_driver` and
      // forgot the manager's, so subscribing now would create a subscription
      // AFTER the teardown that was supposed to have caught it, and nothing
      // would ever cancel it. Same class as a delivery already waiting for the
      // first frame, and the same flag answers both.
      //
      // Returns out of `boot` entirely rather than skipping this block, and
      // that is deliberate: attaching the push-click handler further down to a
      // provider somebody has torn down is the same defect one block later.
      //
      // The driver is NOT disposed here, and an earlier version of this guard
      // that did was disposing it twice. `_driver` is assigned before the
      // await, so the only way to arrive here with the flag set is a teardown
      // inside that await, and by then `dispose()` has already seen `_driver`,
      // disposed it and forgotten the manager's. There is no path that reaches
      // this line holding a driver nobody has torn down.
      if (_disposed) {
        return;
      }

      // The one delivery path, and there used to be two. The cold-start link
      // came in on this stream AND out of `manager.getInitialLink()`, which the
      // Android plugin serves independently of it, so a single tap ran the
      // whole handler chain twice. `app_links`' own README subscribes to
      // `uriLinkStream` alone and calls it "all events (initial link and
      // further)", so the stream is the path that survives and the separate
      // read is gone. `DeeplinkManager.getInitialLink()` stays for a consumer
      // that wants to ask, and nothing here calls it.
      //
      // Captured once, before the first link can arrive: `endOfFrame` asked for
      // again later would wait for ANOTHER frame, and every awaiting delivery
      // resumes in the order it registered, so the links stay in order.
      final Future<void> firstFrame =
          WidgetsFlutterBinding.ensureInitialized().endOfFrame;

      _links = driver.onLink.listen(
        (uri) => unawaited(_deliver(manager, uri, firstFrame)),
      );
    }

    // Route tapped push notifications, when the consumer installed the
    // notifications plugin. An app that ships deep links without push is the
    // normal case and nothing at all is created for it here, so there is no
    // subscription to leak.
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
