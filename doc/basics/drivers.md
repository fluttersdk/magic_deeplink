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
- [Custom Drivers](#custom-drivers)
    - [Implementing the Contract](#implementing-the-contract)
    - [Registering a Custom Driver](#registering-a-custom-driver)
- [Related](#related)

<a name="introduction"></a>
## Introduction

A driver is the platform abstraction layer that delivers raw URI events to the `DeeplinkManager`. Drivers translate platform-specific deep link mechanisms — Universal Links on iOS and macOS, App Links on Android — into a uniform `Stream<Uri>` that the rest of the plugin consumes.

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

Returns `true` when the driver can operate on the current platform. The `DeeplinkServiceProvider` skips driver initialization and stream setup when this returns `false`, so your check must be synchronous. Use `Platform.isAndroid`, `Platform.isIOS`, etc., guarded by a `try/catch` for environments where `dart:io` is unavailable, and check `kIsWeb` before any `Platform` access.

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

Called once by the service provider before any link is consumed. Use this to create platform clients, open channels, or apply configuration values sourced from the `deeplink` config map. Keep this method idempotent — the provider does not guard against duplicate calls.

<a name="getinitiallink"></a>
### getInitialLink

```dart
Future<Uri?> getInitialLink();
```

Returns the URI that cold-started the application, or `null` if the app was launched normally. This is called once after `initialize()` completes. Swallow exceptions internally and return `null` on failure — callers do not expect this method to throw.

<a name="dispose"></a>
### dispose

```dart
void dispose();
```

Releases any resources held by the driver (stream subscriptions, platform channels, timers). Called by the service provider during application teardown. If your driver holds no resources, the body can be left empty.

<a name="applinksdriver"></a>
## AppLinksDriver

`AppLinksDriver` is the default driver. It delegates to the `app_links` package, which handles Universal Links (iOS / macOS) and App Links (Android) without any native Dart code in this plugin.

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
| Android  | Yes — App Links (HTTPS intent filter) |
| iOS      | Yes — Universal Links (apple-app-site-association) |
| macOS    | Yes — Universal Links |
| Web      | No |
| Windows  | No |
| Linux    | No |

`AppLinksDriver.isSupported` returns `false` for web (`kIsWeb`) and for any platform not in the set `{Android, iOS, macOS}`. The service provider will not attempt initialization or stream subscription when `isSupported` is `false`.

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

- [Handlers](https://magic.fluttersdk.com/packages/deeplink/basics/handlers) — Chain-of-responsibility URI handling after the driver emits a link
- [Configuration](https://magic.fluttersdk.com/packages/deeplink/getting-started/configuration) — `config/deeplink.dart` driver selection and options
- [Service Provider](https://magic.fluttersdk.com/packages/deeplink/architecture/service-provider) — Boot lifecycle, driver initialization, and stream wiring
