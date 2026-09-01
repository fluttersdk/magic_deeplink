import 'package:magic/magic.dart';
import '../deeplink_manager.dart';
import '../drivers/app_links_driver.dart';
import '../handlers/onesignal_deeplink_handler.dart';

class DeeplinkServiceProvider extends ServiceProvider {
  DeeplinkServiceProvider(super.app);

  @override
  void register() {
    app.singleton('deeplinks', () => DeeplinkManager());
  }

  @override
  Future<void> boot() async {
    final config = app.make<ConfigRepository>('config');
    final driverName = config.get('deeplink.driver');
    final manager = app.make<DeeplinkManager>('deeplinks');

    if (driverName == 'app_links') {
      final driver = AppLinksDriver();
      manager.setDriver(driver);
      await driver.initialize(config.get('deeplink') ?? {});

      // Connect driver stream to manager
      driver.onLink.listen((uri) {
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
    if (app.bound('notifications')) {
      OneSignalDeeplinkHandler().setup(manager, app.make('notifications'));
    }
  }
}
