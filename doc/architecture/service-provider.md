# DeeplinkServiceProvider

- [Introduction](#introduction)
- [Two-Phase Bootstrap](#two-phase-bootstrap)
- [Register Phase](#register-phase)
- [Boot Phase](#boot-phase)
    - [Driver Initialization](#driver-initialization)
    - [Stream Wiring](#stream-wiring)
    - [Initial Link Handling](#initial-link-handling)
    - [OneSignal Handler Setup](#onesignal-handler-setup)
- [Optional Dependency Handling](#optional-dependency-handling)
- [Registering the Provider](#registering-the-provider)
- [Related](#related)

<a name="introduction"></a>
## Introduction

`DeeplinkServiceProvider` is the bootstrap entry point for the magic_deeplink plugin. It wires together the platform driver, the singleton manager, and optional third-party handlers (OneSignal) using the Magic Framework's IoC container and two-phase provider lifecycle.

The provider lives at `lib/src/providers/deeplink_service_provider.dart` and extends `ServiceProvider` from `package:magic/magic.dart`.

<a name="two-phase-bootstrap"></a>
## Two-Phase Bootstrap

The Magic Framework calls providers in two ordered phases:

| Phase | Method | Constraint |
|-------|--------|------------|
| 1 | `register()` | Sync. Only bind into the container — no other service may be accessed yet. |
| 2 | `boot()` | Async. All providers have been registered. Safe to resolve, configure, and wire services. |

Splitting into two phases guarantees that when `boot()` runs, every binding registered by every other provider is already resolvable from the container.

<a name="register-phase"></a>
## Register Phase

```dart
@override
void register() {
  app.singleton('deeplinks', () => DeeplinkManager());
}
```

`register()` binds a single singleton into the container under the key `'deeplinks'`. `DeeplinkManager` uses the standard singleton factory pattern (`factory DeeplinkManager() => _instance`), so the closure and the factory both guarantee one shared instance exists for the lifetime of the app.

Nothing else happens here. Config is not read, the driver is not created, and no other service is accessed — all of that is deferred to `boot()`.

<a name="boot-phase"></a>
## Boot Phase

`boot()` is `async`. It resolves the already-registered manager and config, then sets up the driver, the live-link stream, the initial link, and the optional OneSignal handler.

```dart
@override
Future<void> boot() async {
  final config = app.make<ConfigRepository>('config');
  final driverName = config.get('deeplink.driver');
  final manager = app.make<DeeplinkManager>('deeplinks');

  // ... driver and handler wiring
}
```

<a name="driver-initialization"></a>
### Driver Initialization

The provider reads `deeplink.driver` from config and creates the matching platform driver. Currently the only supported value is `'app_links'`.

```dart
if (driverName == 'app_links') {
  final driver = AppLinksDriver();
  manager.setDriver(driver);
  await driver.initialize(config.get('deeplink') ?? {});

  // ...
}
```

`driver.initialize()` is awaited — it must complete before the stream is wired or the initial link is fetched. The entire `deeplink` config map is passed to the driver so it can read any platform-specific keys it requires.

<a name="stream-wiring"></a>
### Stream Wiring

After initialization the driver's `onLink` stream is forwarded directly to `manager.handleUri()`:

```dart
driver.onLink.listen((uri) {
  manager.handleUri(uri);
});
```

This connects the platform event source to the handler chain. Every URI the driver emits — Universal Links on iOS, App Links on Android — is dispatched through `manager.handleUri()`, which fans the URI out to all registered handlers and emits it on `manager.onLink`.

<a name="initial-link-handling"></a>
### Initial Link Handling

When the app is cold-started from a deep link, the platform holds the URI until it is explicitly fetched. Fetching it synchronously during boot is unsafe because the app's router is not yet mounted at that point — it finishes initializing after `runApp()` returns, which happens after all providers have booted.

The provider defers the fetch to the next microtask / event-loop turn using `Future.delayed(Duration.zero, ...)`:

```dart
Future.delayed(Duration.zero, () async {
  final uri = await manager.getInitialLink();
  if (uri != null) {
    manager.handleUri(uri);
  }
});
```

`Duration.zero` schedules the callback after the current frame completes, ensuring the router (and any registered handlers) are fully ready before the initial link is dispatched. `manager.getInitialLink()` caches its result, so repeated calls are safe.

<a name="onesignal-handler-setup"></a>
### OneSignal Handler Setup

If the magic_notifications plugin is present and bound, the provider attaches a `OneSignalDeeplinkHandler` that listens for notification-click events and converts them to deep link URIs:

```dart
if (app.bound('notifications')) {
  try {
    final notificationManager = app.make('notifications');
    final driver = (notificationManager as dynamic).pushDriver;
    if (driver != null) {
      final oneSignalHandler = OneSignalDeeplinkHandler();
      oneSignalHandler.setup(
        manager,
        driver.onNotificationClicked as Stream<Map<String, dynamic>>,
      );
    }
  } catch (e) {
    // Silently fail — plugin bound but structure different or stream type mismatch
  }
}
```

`OneSignalDeeplinkHandler.setup()` subscribes to `onNotificationClicked`, extracts a URI from the notification payload (checking keys `url`, `deep_link`, `link`, `uri`), and calls `manager.handleUri()` for any non-null result.

<a name="optional-dependency-handling"></a>
## Optional Dependency Handling

The integration with magic_notifications is entirely optional. The pattern used has three layers of defence:

1. **`app.bound('notifications')`** — guards the entire block. If the plugin was never registered, the block is skipped without error.
2. **`dynamic` cast** — `notificationManager` is accessed as `dynamic` to avoid a compile-time import of `magic_notifications`. This keeps magic_deeplink free of a hard package dependency.
3. **`try-catch`** — the push driver accessor and stream cast can throw if the notifications plugin has a different internal structure or version. The `catch` block silently discards the error so a notifications misconfiguration never breaks deep linking.

This pattern should be followed whenever magic_deeplink optionally integrates with another plugin.

<a name="registering-the-provider"></a>
## Registering the Provider

Add the provider to the `providers` list in your app's `config/app.dart`:

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

Map<String, dynamic> get appConfig => {
  'app': {
    'providers': [
      // ... other providers
      (app) => DeeplinkServiceProvider(app),
    ],
  },
  'deeplink': {
    'driver': 'app_links',
    // platform-specific keys passed through to driver.initialize()
  },
};
```

The provider must be listed **after** any provider that registers `'notifications'` so that `app.bound('notifications')` returns the correct result during boot.

<a name="related"></a>
## Related

- [DeeplinkManager](https://magic.fluttersdk.com/packages/deeplink/architecture/deeplink-manager) — singleton manager: handler chain, stream, initial link cache
- [Drivers](https://magic.fluttersdk.com/packages/deeplink/basics/drivers) — platform driver wrapping the `app_links` package
- [Handlers](https://magic.fluttersdk.com/packages/deeplink/basics/handlers) — notification-to-URI bridge
- [Magic Framework — Service Providers](https://magic.fluttersdk.com/getting-started/service-providers) — two-phase lifecycle reference
