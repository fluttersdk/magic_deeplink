# Installation

- [Introduction](#introduction)
- [Requirements](#requirements)
- [Installing the Package](#installing-the-package)
- [Running the Install Command](#running-the-install-command)
- [Registering the Service Provider](#registering-the-service-provider)
- [Injecting the Config Factory](#injecting-the-config-factory)
- [Configuration Reference](#configuration-reference)
- [Next Steps](#next-steps)

<a name="introduction"></a>
## Introduction

`magic_deeplink` adds Universal Links (iOS) and App Links (Android) to your Magic application. It follows the same ServiceProvider + driver + handler pattern used throughout the framework, so it wires up in exactly the same way as every other Magic plugin.

Under the hood the package delegates all platform stream handling to [`app_links`](https://pub.dev/packages/app_links). There is no native Android or iOS code in this plugin — platform support lives entirely inside `app_links`.

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
  magic_deeplink: ^0.0.1
```

Then fetch dependencies:

```bash
flutter pub get
```

<a name="running-the-install-command"></a>
## Running the Install Command

Magic Deeplink ships its own CLI command. Run it from your project root to scaffold the configuration file and inject the provider automatically:

```bash
dart run magic_deeplink:install
```

The command performs the following steps:

1. **Validates** that `lib/config/app.dart` exists (Magic must be installed first).
2. **Creates** `lib/config/deeplink.dart` with sensible defaults.
3. **Injects** `DeeplinkServiceProvider` into the `providers` list in `lib/config/app.dart`.
4. **Injects** `() => deeplinkConfig` into the `configFactories` list in `lib/main.dart`.

> [!NOTE]
> If `lib/config/deeplink.dart` already exists the command skips the write and prints a warning. Pass `--force` to overwrite an existing configuration file.

```bash
dart run magic_deeplink:install --force
```

<a name="registering-the-service-provider"></a>
## Registering the Service Provider

If you ran `dart run magic_deeplink:install`, the provider was already injected. The relevant section of `lib/config/app.dart` will look like this:

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

<a name="next-steps"></a>
## Next Steps

Now that the plugin is installed and wired up:

- **[Configuration](https://magic.fluttersdk.com/packages/deeplink/getting-started/configuration)** — Learn how to customise paths, schemes, and platform settings.
- **[Handlers](https://magic.fluttersdk.com/packages/deeplink/basics/handlers)** — Add your own URI handlers with `RouteDeeplinkHandler`.
- **[CLI Tools](https://magic.fluttersdk.com/packages/deeplink/basics/cli)** — Use `dart run magic_deeplink:generate` to produce the Apple App Site Association and Android Asset Links files.
