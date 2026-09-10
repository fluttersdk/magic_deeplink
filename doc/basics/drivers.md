# Drivers

- [Introduction](#introduction)
- [The DeeplinkDriver Contract](#the-deeplink-driver-contract)
    - [name](#name)
    - [isSupported](#issupported)
    - [onLink](#onlink)
    - [initialize](#initialize)
    - [getInitialLink](#getinitiallink)
    - [dispose](#dispose)
- [AppLinksDriver](#applinksdriver)
    - [Platform Support](#platform-support)
    - [Web, in detail](#web)
- [Custom Drivers](#custom-drivers)
    - [Implementing the Contract](#implementing-the-contract)
    - [Registering a Custom Driver](#registering-a-custom-driver)
- [Related](#related)

<a name="introduction"></a>
## Introduction

A driver is the platform abstraction layer that delivers raw URI events to the `DeeplinkManager`. Drivers translate platform-specific deep link mechanisms (Universal Links on iOS and macOS, App Links on Android) into a uniform `Stream<Uri>` that the rest of the plugin consumes.

The plugin ships with `AppLinksDriver`, which covers all supported native platforms via the [`app_links`](https://pub.dev/packages/app_links) package. If you need to source URIs from a custom mechanism (push notifications, in-app QR scanning, test harnesses), you can implement the `DeeplinkDriver` contract and register it in place of the default driver.

<a name="the-deeplink-driver-contract"></a>
## The DeeplinkDriver Contract

All drivers extend the abstract class `DeeplinkDriver`, defined in `lib/src/drivers/deeplink_driver.dart`:

```dart
abstract class DeeplinkDriver {
  String get name;
  bool get isSupported;
  Future<void> initialize(Map<String, dynamic> config);
  Future<Uri?> getInitialLink();
  Stream<Uri> get onLink;
  void dispose();
}
```

<a name="name"></a>
### name

```dart
String get name;
```

A stable identifier for the driver. Used for logging and diagnostics. Return a lowercase, hyphenated string, for example `'app_links'` or `'my-custom-driver'`.

<a name="issupported"></a>
### isSupported

```dart
bool get isSupported;
```

Returns `true` when the driver can operate on the current platform. The `DeeplinkServiceProvider` skips driver initialization and stream setup entirely when this returns `false`, so your check must be synchronous. `AppLinksDriver` answers this from `Platform.isAndroid || Platform.isIOS || Platform.isMacOS`, guarded by a `try/catch` in case `dart:io` is unavailable at runtime.

A custom driver that needs to run on web no longer follows the single-class-with-a-`kIsWeb`-branch shape `AppLinksDriver` used to: it is now a conditional-export barrel choosing between a `dart:io` arm and a `dart:js_interop` (web) arm at compile time, so `dart:io` is imported only where it is actually used. See [AppLinksDriver](#applinksdriver) for the shape.

<a name="onlink"></a>
### onLink

```dart
Stream<Uri> get onLink;
```

A broadcast stream that emits every URI received while the application is running. The `DeeplinkServiceProvider` subscribes to this stream during the boot phase and forwards each emission to `DeeplinkManager.handleUri()`. Return `Stream.empty()` on unsupported platforms.

<a name="initialize"></a>
### initialize

```dart
Future<void> initialize(Map<String, dynamic> config);
```

Called once by the service provider before any link is consumed. Use this to create platform clients, open channels, or apply configuration values sourced from the `deeplink` config map. Keep this method idempotent: the provider does not guard against duplicate calls.

<a name="getinitiallink"></a>
### getInitialLink

```dart
Future<Uri?> getInitialLink();
```

Returns the URI that cold-started the application, or `null` if the app was launched normally. This is called once after `initialize()` completes. Swallow exceptions internally and return `null` on failure: callers do not expect this method to throw.

<a name="dispose"></a>
### dispose

```dart
void dispose();
```

Releases any resources held by the driver (stream subscriptions, platform channels, timers). Called by the service provider during application teardown. If your driver holds no resources, the body can be left empty.

<a name="applinksdriver"></a>
## AppLinksDriver

`AppLinksDriver` is the default driver, and the exported name is a conditional-export barrel over three arms selected at compile time:

```dart
export 'app_links_driver_stub.dart'
    if (dart.library.js_interop) 'app_links_driver_web.dart'
    if (dart.library.io) 'app_links_driver_io.dart';
```

The `dart:io` arm wraps the `app_links` package and is the only one that talks to a real platform channel: it answers `isSupported` from `Platform.isAndroid || Platform.isIOS || Platform.isMacOS`, and delegates `getInitialLink()` and `onLink` to `app_links` directly.

The web arm is a deliberate no-op, not a partial implementation waiting to be filled in: `isSupported` is `false`, `getInitialLink()` returns `null`, `onLink` is `Stream<Uri>.empty()`, and `initialize`/`dispose` do nothing. It is not wired to the `app_links_web` package, because that package reads the boot-time `location.href` once and never reacts to later navigation, while GoRouter already owns the browser's address bar under this app's path URL strategy; routing the same navigation through both would duplicate it, not add coverage.

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

// AppLinksDriver is registered automatically by DeeplinkServiceProvider.
// You only need to interact with it directly when writing custom boot logic.
final driver = AppLinksDriver();
await driver.initialize({});

final initial = await driver.getInitialLink(); // Uri? from cold start
driver.onLink.listen((uri) {
  // Handle foreground links
});
```

<a name="platform-support"></a>
### Platform Support

| Platform | Supported |
|----------|-----------|
| Android  | Yes: App Links (HTTPS intent filter) |
| iOS      | Yes: Universal Links (apple-app-site-association) |
| macOS    | Yes: Universal Links |
| Web      | No driver, but see below: deep links still work, by two other routes |
| Windows  | No |
| Linux    | No |

On web, `AppLinksDriver` resolves to the web arm above, whose `isSupported` is unconditionally `false`. On Android, iOS and macOS it resolves to the `dart:io` arm, whose `isSupported` follows `Platform.isAndroid || Platform.isIOS || Platform.isMacOS`; that check answers `false` on Windows and Linux too, and the stub arm (also `isSupported == false`) covers any remaining target. The service provider will not attempt initialization or stream subscription when `isSupported` is `false`.

<a name="web"></a>
### Web, in detail

"No driver" is not "no deep links", and reading the table alone has sent people away from a working feature. Web has two routes into a screen and this package owns neither driver, so both are easy to leave half configured.

**A tapped push, with the tab open, does reach the handler chain.** The push bridge is wired OUTSIDE the `isSupported` gate in `DeeplinkServiceProvider.boot()`, so it exists on web exactly as it does on mobile: `OneSignalWebDriver` publishes the click, the notification manager republishes it, and `OneSignalDeeplinkHandler` routes it with `DeeplinkSource.push`. Put the link in the notification's `additionalData` under `url`, `deep_link`, `link` or `uri`, the same keys mobile reads. A launch URL set on the OneSignal side alone is NOT read by the bridge.

**An address-bar link is GoRouter's job, not this package's,** which is why the driver is inert rather than wired to `app_links_web`: that package reads `location.href` once at boot and never reacts to later navigation, so routing the same URI twice would be the bug. But GoRouter only gets a clean path when two things outside this package are true, and neither fails loudly:

1. `routing.url_strategy` is `'path'` in the app's routing config. Without it Flutter uses the hash strategy and `https://app.example.com/incidents/5` is not a route at all.
2. The web host rewrites unknown paths to `index.html`. Without it the same URL is a plain 404 from nginx or whatever serves the build, and Flutter never boots.

**A push clicked with no tab open is the second route, not the first.** No Dart code is running, so nothing reads `additionalData`; the service worker opens the notification's launch URL, which arrives as an ordinary page load and therefore needs both prerequisites above.

<a name="custom-drivers"></a>
## Custom Drivers

<a name="implementing-the-contract"></a>
### Implementing the Contract

Extend `DeeplinkDriver` and implement every member of the contract. The example below shows a driver that emits URIs received from a push notification payload:

```dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

class PushNotificationDriver extends DeeplinkDriver {
  final StreamController<Uri> _controller =
      StreamController<Uri>.broadcast();

  @override
  String get name => 'push-notification';

  @override
  bool get isSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    // Subscribe to your notification service here and pipe URIs
    // into _controller whenever a deep link payload arrives.
  }

  @override
  Future<Uri?> getInitialLink() async {
    // Return a URI if the app was cold-started from a notification,
    // or null if no link was attached to the launch payload.
    return null;
  }

  @override
  Stream<Uri> get onLink => _controller.stream;

  /// Call this from your notification handler to emit a URI.
  void emit(Uri uri) => _controller.add(uri);

  @override
  void dispose() {
    _controller.close();
  }
}
```

<a name="registering-a-custom-driver"></a>
### Registering a Custom Driver

Pass your driver to `DeeplinkManager.setDriver()` before the service provider's `boot()` phase completes. The canonical place is inside a custom service provider's `boot()` method, or directly in your `AppServiceProvider`:

```dart
import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

class AppServiceProvider extends ServiceProvider {
  @override
  void register() {}

  @override
  Future<void> boot() async {
    final manager = app.make<DeeplinkManager>('deeplinks');
    manager.setDriver(PushNotificationDriver());
  }
}
```

You can also set the driver imperatively at any point before the first link is consumed:

```dart
DeeplinkManager().setDriver(PushNotificationDriver());
```

> [!NOTE]
> `setDriver()` replaces any previously registered driver. Call it before the `onLink` stream is subscribed to, otherwise the existing subscription (created during boot) will continue reading from the old driver.

<a name="related"></a>
## Related

- [Handlers](https://magic.fluttersdk.com/packages/deeplink/basics/handlers): Chain-of-responsibility URI handling after the driver emits a link
- [Configuration](https://magic.fluttersdk.com/packages/deeplink/getting-started/configuration): `config/deeplink.dart` driver selection and options
- [Service Provider](https://magic.fluttersdk.com/packages/deeplink/architecture/service-provider): Boot lifecycle, driver initialization, and stream wiring
