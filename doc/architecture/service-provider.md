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

If the magic_notifications plugin is present and bound, the provider attaches a `OneSignalDeeplinkHandler` that listens for tapped-push events and converts them to deep link URIs:

```dart
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
```

The handler is HELD rather than discarded, so [`dispose()`](#provider-teardown) can reach it.

`setup()` takes the notification MANAGER, not a stream, and subscribes to its `onPushClicked` stream, which the manager owns from construction and republishes onto whenever a driver is attached later. That is what makes this independent of provider order: only the `'notifications'` binding needs to exist at this point, never a resolved push driver, because every provider has registered by the time any of them boots. `OneSignalDeeplinkHandler` then extracts a URI from the notification payload (checking keys `url`, `deep_link`, `link`, `uri`) and calls `manager.handleUri()` for any non-null result.

<a name="optional-dependency-handling"></a>
## Optional Dependency Handling

The integration with magic_notifications is entirely optional. The pattern used has three layers of defence:

1. **`app.bound('notifications')`** — guards the entire block. If the plugin was never registered, the block is skipped without error.
2. **`dynamic` resolution inside the handler**: `app.make('notifications')` is handed to the handler untyped, and `OneSignalDeeplinkHandler` reads `onPushClicked` off it structurally rather than importing `magic_notifications` and naming its type. This keeps magic_deeplink free of a hard package dependency. When the bound manager is too old to publish `onPushClicked`, or publishes something that is not a `Stream`, the handler reports the mismatch through magic's `Log` (guarded by `Magic.bound('log')`) instead of throwing, so a notifications version mismatch degrades deep linking rather than breaking app boot.

3. **A `try`/`catch` around the resolution**, reporting at error level through the same `Log` seam. `app.make('notifications')` runs the binding factory and `onPushClicked` is a getter, so either can throw, and the handler only answers `NoSuchMethodError` by name (that one means "this build is too old"). Anything else, a `StateError` out of an uninitialised manager for instance, would otherwise escape. That matters more here than it looks: magic's `Application.boot` awaits providers in a bare loop with no error handling of its own, so an escaping throw does not degrade deep linking, it aborts app boot and every provider registered after this one, over a plugin that is optional by design.

This is not a swallowing catch. The wiring this replaced had a `catch (e)` whose body was two comment lines, and that is why the feature stayed inert across two years of releases. This one names what failed, then lets boot continue.

This pattern should be followed whenever magic_deeplink optionally integrates with another plugin.

<a name="provider-teardown"></a>
## Provider Teardown

`DeeplinkServiceProvider.dispose()` drops everything `boot()` wired: the push-click handler, the driver's link subscription, the driver itself, and the manager's own reference to it (`DeeplinkManager.forgetDriver()`, which the manager has always exposed and nothing called). The scheduled initial-link read checks a disposed flag on both sides of its await, since a `Future.delayed` offers no handle to cancel.

```dart
await provider.dispose();
```

It is provider-level rather than handler-level on purpose. `doc/basics/handlers.md` tells a consumer to call teardown from their service provider, so a `dispose()` reaching only the push handler would read as tearing the provider down while leaving the driver running. It is also idempotent, because a consumer calling it does not know which parts a given deployment actually wired.

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

The provider's position relative to any provider registering `'notifications'` does not matter. `app.bound('notifications')` is checked during boot, after every provider has registered, and the OneSignal handler subscribes to the notification manager's own stream rather than to a driver, so it does not need that provider to have booted yet either.

<a name="related"></a>
## Related

- [DeeplinkManager](https://magic.fluttersdk.com/packages/deeplink/architecture/deeplink-manager) — singleton manager: handler chain, stream, initial link cache
- [Drivers](https://magic.fluttersdk.com/packages/deeplink/basics/drivers) — platform driver wrapping the `app_links` package
- [Handlers](https://magic.fluttersdk.com/packages/deeplink/basics/handlers) — notification-to-URI bridge
- [Magic Framework — Service Providers](https://magic.fluttersdk.com/getting-started/service-providers) — two-phase lifecycle reference
