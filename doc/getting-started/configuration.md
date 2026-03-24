# Configuration

- [Introduction](#introduction)
- [The Deeplink Config File](#deeplink-config-file)
- [Driver Selection](#driver-selection)
- [iOS Configuration](#ios-configuration)
- [Android Configuration](#android-configuration)
- [Paths](#paths)
- [Accessing Configuration Values](#accessing-configuration-values)
- [CLI Generate Command](#cli-generate-command)

<a name="introduction"></a>
## Introduction

The `magic_deeplink` plugin is configured via a single Dart file at `lib/config/deeplink.dart` in your consumer project. This file is generated automatically when you run the install command, and contains all values required for both runtime deep link handling and server-side asset file generation.

```bash
dart run magic_deeplink:install
```

The install command scaffolds `lib/config/deeplink.dart` with placeholder values. Replace the placeholders with your real credentials before running your app or generating server-side files.

<a name="deeplink-config-file"></a>
## The Deeplink Config File

The generated `lib/config/deeplink.dart` exports a single top-level getter that returns a nested `Map<String, dynamic>`:

```dart
Map<String, dynamic> get deeplinkConfig => {
  'deeplink': {
    'enabled': true,
    'driver': 'app_links',
    'domain': 'example.com',
    'scheme': 'https',

    'ios': {
      'team_id': 'YOUR_TEAM_ID',
      'bundle_id': 'com.example.app',
    },

    'android': {
      'package_name': 'com.example.app',
      'sha256_fingerprints': [
        'YOUR_SHA256_FINGERPRINT',
      ],
    },

    'paths': [
      '/*',
    ],
  },
};
```

Register it with `Magic.init()` alongside your other config factories:

```dart
await Magic.init(
  configFactories: [
    appConfig,
    deeplinkConfig,
  ],
);
```

> [!NOTE]
> All keys under `'deeplink'` are accessible at runtime via `Config.get('deeplink.<key>')` using dot notation. The `DeeplinkServiceProvider` reads from this namespace during the boot phase.

<a name="driver-selection"></a>
## Driver Selection

The `'driver'` key determines which platform abstraction is used to receive incoming links. Currently, only one driver is available:

| Value | Package | Description |
|-------|---------|-------------|
| `'app_links'` | `app_links` | Universal Links (iOS) and App Links (Android) via the `app_links` package |

```dart
'driver': 'app_links',
```

`DeeplinkServiceProvider.boot()` reads this value and instantiates the matching driver. If the value does not match a known driver, no driver is registered and deep links will not be handled.

> [!NOTE]
> `'app_links'` is the only supported driver in the current release. Additional drivers can be contributed by implementing the `DeeplinkDriver` abstract class.

<a name="ios-configuration"></a>
## iOS Configuration

iOS Universal Links require an `apple-app-site-association` (AASA) file hosted at your domain. The `ios` block provides the values needed to generate that file.

```dart
'ios': {
  'team_id': 'ABCDE12345',
  'bundle_id': 'com.example.app',
},
```

| Key | Type | Description |
|-----|------|-------------|
| `team_id` | `String` | Your 10-character Apple Developer Team ID, found in the Apple Developer portal under Membership. |
| `bundle_id` | `String` | The bundle identifier of your iOS app (e.g. `com.example.app`). Must match the value in `Runner.xcodeproj`. |

The `appID` field inside `apple-app-site-association` is constructed as `TEAM_ID.BUNDLE_ID`:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "ABCDE12345.com.example.app",
        "paths": ["/*"]
      }
    ]
  }
}
```

> [!NOTE]
> The AASA file must be served over HTTPS at `https://<domain>/.well-known/apple-app-site-association` with `Content-Type: application/json` and no redirect. Apple's CDN caches this file aggressively — allow up to 24 hours for updates to propagate.

<a name="android-configuration"></a>
## Android Configuration

Android App Links require an `assetlinks.json` file hosted at your domain. The `android` block provides the values needed to generate that file.

```dart
'android': {
  'package_name': 'com.example.app',
  'sha256_fingerprints': [
    'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99',
  ],
},
```

| Key | Type | Description |
|-----|------|-------------|
| `package_name` | `String` | The Android application ID (e.g. `com.example.app`). Must match `applicationId` in `android/app/build.gradle`. |
| `sha256_fingerprints` | `List<String>` | One or more SHA-256 certificate fingerprints. Include both your release and debug signing certificates during development. |

To retrieve the SHA-256 fingerprint for your keystore:

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

Each fingerprint produces a separate entry in `assetlinks.json`. Supply multiple fingerprints when you need to support several signing configurations (e.g. debug, release, CI):

```dart
'sha256_fingerprints': [
  'AA:BB:CC:...',  // debug keystore
  'DD:EE:FF:...',  // release keystore
],
```

> [!NOTE]
> The `assetlinks.json` file must be served at `https://<domain>/.well-known/assetlinks.json` with `Content-Type: application/json`. Android verifies this file at install time, not at link-click time.

<a name="paths"></a>
## Paths

The `paths` array controls which URL paths your app claims to handle. This value is used in both the iOS `apple-app-site-association` and to filter which URIs the runtime driver passes to your handlers.

```dart
'paths': [
  '/*',
],
```

The default `'/*'` matches all paths under your domain. You can restrict this to specific prefixes:

```dart
'paths': [
  '/app/*',
  '/invite/*',
  '/reset-password',
],
```

| Pattern | Matches |
|---------|---------|
| `'/*'` | All paths |
| `'/app/*'` | Any path starting with `/app/` |
| `'/invite/*'` | Any path starting with `/invite/` |
| `'/reset-password'` | Exact path `/reset-password` only |

> [!NOTE]
> Android App Links use a different matching mechanism in `assetlinks.json` — the `assetlinks.json` grants your app permission for the entire domain. Path-level filtering on Android is handled by your intent filters in `AndroidManifest.xml`, not by the `paths` array here. The `paths` array in this config primarily drives the iOS AASA file and the CLI generate output.

<a name="accessing-configuration-values"></a>
## Accessing Configuration Values

At runtime, all values are accessible via the `Config` facade using dot notation with the `deeplink` namespace:

```dart
// Check whether deep linking is enabled
final enabled = Config.get<bool>('deeplink.enabled', true);

// Get the active driver name
final driver = Config.get<String>('deeplink.driver');

// Get the domain
final domain = Config.get<String>('deeplink.domain');

// Get the iOS team ID
final teamId = Config.get<String>('deeplink.ios.team_id');

// Get the Android package name
final packageName = Config.get<String>('deeplink.android.package_name');
```

The `DeeplinkServiceProvider` passes the entire `deeplink` map to the driver's `initialize()` method during `boot()`:

```dart
await driver.initialize(config.get('deeplink') ?? {});
```

<a name="cli-generate-command"></a>
## CLI Generate Command

The `generate` command reads `lib/config/deeplink.dart` automatically and uses your config values to produce the server-side asset files. CLI flags override config file values when both are present.

```bash
dart run magic_deeplink:generate --output ./public
```

This creates two files in the specified output directory:

| File | Platform | Hosting path |
|------|----------|-------------|
| `apple-app-site-association` | iOS | `/.well-known/apple-app-site-association` |
| `assetlinks.json` | Android | `/.well-known/assetlinks.json` |

You can override individual values without editing the config file using CLI flags:

```bash
dart run magic_deeplink:generate \
  --output ./public \
  --team-id ABCDE12345 \
  --bundle-id com.example.app \
  --package-name com.example.app \
  --sha256-fingerprints AA:BB:CC:... \
  --paths /app/* \
  --paths /invite/*
```

| Flag | Config key | Description |
|------|------------|-------------|
| `--team-id` | `deeplink.ios.team_id` | Apple Developer Team ID |
| `--bundle-id` | `deeplink.ios.bundle_id` | iOS bundle identifier |
| `--package-name` | `deeplink.android.package_name` | Android package name |
| `--sha256-fingerprints` | `deeplink.android.sha256_fingerprints` | SHA-256 fingerprint(s); repeatable |
| `--paths` | `deeplink.paths` | URL paths to handle; repeatable |
| `--output` | — | Output directory (default: `public`) |

> [!NOTE]
> When `lib/config/deeplink.dart` is present, the generate command reads it first and uses those values as defaults. CLI flags take precedence over config file values, allowing you to override specific fields for different environments (e.g. a CI pipeline using separate signing certificates).
