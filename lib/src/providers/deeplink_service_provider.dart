import 'package:fluttersdk_magic/fluttersdk_magic.dart';
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

    // Setup OneSignal handler if notifications plugin is available
    if (app.bound('notifications')) {
      try {
        final notificationManager = app.make('notifications');
        // access dynamically to avoid hard dependency
        final driver = (notificationManager as dynamic).pushDriver;
        if (driver != null) {
          final oneSignalHandler = OneSignalDeeplinkHandler();
          // Assume driver has onNotificationClicked stream
          oneSignalHandler.setup(
            manager,
            driver.onNotificationClicked as Stream<Map<String, dynamic>>,
          );
        }
      } catch (e) {
        // Plugin might be bound but structure different or stream type mismatch
        // Silently fail or log in debug
      }
    }
  }
}
