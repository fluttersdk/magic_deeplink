# Installation

- [Introduction](#introduction)
- [Requirements](#requirements)
- [Installing the Package](#installing-the-package)
- [Running the Install Command](#running-the-install-command)
- [Registering the Service Provider](#registering-the-service-provider)
- [Injecting the Config Factory](#injecting-the-config-factory)
- [Registering a Route Handler](#registering-a-route-handler)
- [Configuration Reference](#configuration-reference)
- [Platform Setup](#platform-setup)
  - [iOS: Associated Domains and Info.plist](#ios-associated-domains-and-infoplist)
  - [Android: Intent Filter and Manifest](#android-intent-filter-and-manifest)
- [Next Steps](#next-steps)

<a name="introduction"></a>
## Introduction

`magic_deeplink` adds Universal Links (iOS) and App Links (Android) to your Magic application. It follows the same ServiceProvider + driver + handler pattern used throughout the framework, so it wires up in exactly the same way as every other Magic plugin.

Under the hood the package delegates all platform stream handling to [`app_links`](https://pub.dev/packages/app_links) on Android, iOS and macOS; there is no native Dart plugin code of its own. That does not remove the platform setup an operating system requires before it will hand your app a link at all: an iOS entitlement, an Android intent filter, and a switch on each platform that keeps Flutter's own deep link handler out of the way. See [Platform Setup](#platform-setup) below.

<a name="requirements"></a>
## Requirements

- **Dart SDK**: 3.6.0 or higher
- **Flutter**: 3.27.0 or higher
- **Magic Framework** installed and bootstrapped (`lib/config/app.dart` present)

<a name="installing-the-package"></a>
## Installing the Package

Add `magic_deeplink` to your Flutter project:

```bash
flutter pub add magic_deeplink
```

Or add it manually to `pubspec.yaml`:

```yaml
dependencies:
  magic_deeplink: ^0.1.3
```

Then fetch dependencies:

```bash
flutter pub get
```

<a name="running-the-install-command"></a>
## Running the Install Command

The command is host-dispatched via `fluttersdk_artisan` (add `MagicDeeplinkArtisanProvider` to your app's `lib/config/artisan.dart`, see [CLAUDE.md](../../CLAUDE.md)). Run it from your project root to scaffold the configuration file and inject the provider automatically:

```bash
dart run <app>:artisan deeplink:install
```

The command performs the following steps:

1. **Validates** that `lib/config/app.dart` exists (Magic must be installed first).
2. **Creates** `lib/config/deeplink.dart` with sensible defaults.
3. **Injects** `DeeplinkServiceProvider` into the `providers` list in `lib/config/app.dart`.
4. **Injects** `() => deeplinkConfig` into the `configFactories` list in `lib/main.dart`.

> [!NOTE]
> If `lib/config/deeplink.dart` already exists the command skips the write and prints a warning. Pass `--force` to overwrite an existing configuration file.

```bash
dart run <app>:artisan deeplink:install --force
```

<a name="registering-the-service-provider"></a>
## Registering the Service Provider

If you ran `dart run <app>:artisan deeplink:install`, the provider was already injected. The relevant section of `lib/config/app.dart` will look like this:

```dart
import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart'; // injected by install

final appConfig = {
  'app': {
    'name': Env.get('APP_NAME', 'My App'),
    'providers': [
      (app) => RouteServiceProvider(app),
      (app) => AppServiceProvider(app),
      (app) => DeeplinkServiceProvider(app), // injected by install
    ],
  },
};
```

> [!TIP]
> `DeeplinkServiceProvider` registers `DeeplinkManager` as a singleton under the `'deeplinks'` key in the IoC container. You can resolve it anywhere with `app.make<DeeplinkManager>('deeplinks')`.

<a name="injecting-the-config-factory"></a>
## Injecting the Config Factory

The install command also adds the deeplink config factory to `Magic.init()` in `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';
import 'config/app.dart';
import 'config/deeplink.dart'; // injected by install

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    configFactories: [
      () => appConfig,
      () => deeplinkConfig, // injected by install
    ],
  );

  runApp(MagicApplication(title: 'My App'));
}
```

<a name="registering-a-route-handler"></a>
## Registering a Route Handler

The install command wires the driver and the provider, but it registers no handler: `DeeplinkServiceProvider.boot()` never constructs a `RouteDeeplinkHandler` on its own, because it has no way to know which paths your app claims. Register one yourself, in your own service provider's `boot()`, after the paths in your config are settled:

```dart
import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

class AppServiceProvider extends ServiceProvider {
  @override
  Future<void> boot() async {
    DeeplinkManager().registerHandler(
      RouteDeeplinkHandler(
        paths: app.make<ConfigRepository>('config').get('deeplink.paths'),
      ),
    );
  }
}
```

See [Handlers](https://magic.fluttersdk.com/packages/deeplink/basics/handlers) for the full contract and for writing a custom handler.

<a name="configuration-reference"></a>
## Configuration Reference

The generated `lib/config/deeplink.dart` looks like this out of the box:

```dart
Map<String, dynamic> get deeplinkConfig => {
  'deeplink': {
    'enabled': true,
    'driver': 'app_links',   // only supported driver
    'domain': 'example.com', // your Universal Link / App Link domain
    'scheme': 'https',

    'ios': {
      'team_id': 'YOUR_TEAM_ID',     // Apple Developer Team ID
      'bundle_id': 'com.example.app', // app bundle identifier
    },

    'android': {
      'package_name': 'com.example.app',
      'sha256_fingerprints': [
        'YOUR_SHA256_FINGERPRINT', // keystore SHA-256, colon-separated
      ],
    },

    'paths': [
      '/*', // path patterns handled as deep links
    ],
  },
};
```

Replace `example.com`, the team/bundle identifiers, and the SHA-256 fingerprint with your real values before deploying.

> [!NOTE]
> The `driver` key must be `'app_links'`. It is the only driver included with this package. Additional drivers can be added by implementing the `DeeplinkDriver` contract.

<a name="platform-setup"></a>
## Platform Setup

An operating system will not hand your app a link until you tell it your app owns the domain, and Flutter's own deep link handler will race the `app_links` driver this package wires in unless you switch it off. Neither step is automated beyond the one plist key noted below; both are one-time edits to the native project.

<a name="ios-associated-domains-and-infoplist"></a>
### iOS: Associated Domains and Info.plist

1. **Add the Associated Domains capability.** In Xcode, open the `Runner` target's Signing & Capabilities tab, add "Associated Domains", and add an entry of the form `applinks:<your-domain>` (e.g. `applinks:example.com`). This sets the `com.apple.developer.associated-domains` entitlement:

   ```xml
   <key>com.apple.developer.associated-domains</key>
   <array>
       <string>applinks:example.com</string>
   </array>
   ```

2. **Turn off Flutter's own deep link handler.** `app_links` owns link delivery in this package; Flutter's default handler competing for the same link is what `flutter_deeplinking_enabled` avoids on Android. On iOS the equivalent switch is the `FlutterDeepLinkingEnabled` key in `ios/Runner/Info.plist`, set to `false`:

   ```xml
   <key>FlutterDeepLinkingEnabled</key>
   <false/>
   ```

   The install command applies this key for you (`install.yaml`'s `native.ios.info_plist`), so a fresh `deeplink:install` run needs no manual edit here. Re-check it if your project predates this release, or if something else in your project's `Info.plist` template has since overwritten it.

3. **Host the `apple-app-site-association` file.** Generate it with `dart run <app>:artisan deeplink:generate --output ./public` and upload it to `https://<your-domain>/.well-known/apple-app-site-association`, served over HTTPS with no redirect.

<a name="android-intent-filter-and-manifest"></a>
### Android: Intent Filter and Manifest

1. **Add the intent filter.** Inside the `<activity>` element for `.MainActivity` in `android/app/src/main/AndroidManifest.xml`, add an autoVerify intent filter with a `<data>` element for both `http` and `https` (Android's own guidance: "The intent filter must include `<data>` elements for both `http` and `https` schemes."):

   ```xml
   <activity
       android:name=".MainActivity"
       android:exported="true"
       ...>
       <intent-filter android:autoVerify="true">
           <action android:name="android.intent.action.VIEW" />
           <category android:name="android.intent.category.DEFAULT" />
           <category android:name="android.intent.category.BROWSABLE" />

           <data android:scheme="http" android:host="example.com" />
           <data android:scheme="https" android:host="example.com" />
       </intent-filter>
   </activity>
   ```

2. **Turn off Flutter's own deep link handler, inside `<activity>`.** Add this `<meta-data>` element inside the same `<activity>` element as the intent filter above, not inside `<application>`:

   ```xml
   <meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
   ```

   This one is **not** applied by `deeplink:install`. Artisan's `XmlEditor` (the shared engine every plugin's `native.android.meta_data` key runs through) inserts `<meta-data>` entries into `<application>`, and Flutter reads this specific key from `<activity>`; automating it through that key would silently write a `<meta-data>` entry Flutter never looks at, passing every check while doing nothing. Add it by hand.

3. **Host the `assetlinks.json` file.** Generate it with `dart run <app>:artisan deeplink:generate --output ./public` and upload it to `https://<your-domain>/.well-known/assetlinks.json`. Android verifies it at install time, not at link-click time.

<a name="verify"></a>
## Verify the install before you reach for a device

```bash
dart run <app>:artisan deeplink:doctor
```

Every way of getting this install wrong is silent. A `<meta-data>` on the wrong element, a missing `<data>` scheme, an association file that names a different bundle, a provider that never reached `lib/config/app.dart`: none of them throws, none of them logs, and the only symptom is a link that opens the browser. The doctor reads the project's own files and says which prerequisite is actually in place, including the Dart wiring that makes every platform file matter.

Add `--remote` to also fetch both association files from the live domain, which is the half a repo-only check cannot see:

```bash
dart run <app>:artisan deeplink:doctor --remote
```

What it can never prove is that a real device matches an incoming link to this app: `swcutil verify` needs root and Android verifies at install time. The last mile is always a real device, and on iOS it must be a **profile or release** build, since iOS refuses to launch a debug Flutter build from a link or from the home screen.

<a name="next-steps"></a>
## Next Steps

Now that the plugin is installed and wired up:

- **[Configuration](https://magic.fluttersdk.com/packages/deeplink/getting-started/configuration)**: Learn how to customise paths, schemes, and platform settings.
- **[Handlers](https://magic.fluttersdk.com/packages/deeplink/basics/handlers)**: Add your own URI handlers with `RouteDeeplinkHandler`.
- **[CLI Tools](https://magic.fluttersdk.com/packages/deeplink/basics/cli)**: Use `dart run <app>:artisan deeplink:generate` to produce the Apple App Site Association and Android Asset Links files.
