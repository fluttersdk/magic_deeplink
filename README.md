<p align="center">
  <img src="https://raw.githubusercontent.com/fluttersdk/magic/master/.github/magic-logo.svg" width="120" alt="Magic Logo" />
</p>

<h1 align="center">Magic Deeplink</h1>

<p align="center">
  <strong>Universal Links & App Links for the Magic Framework.</strong><br/>
  One unified API for deep linking on iOS and Android — powered by <code>app_links</code>.
</p>

<p align="center">
  <a href="https://pub.dev/packages/magic_deeplink"><img src="https://img.shields.io/pub/v/magic_deeplink.svg" alt="pub.dev version" /></a>
  <a href="https://github.com/fluttersdk/magic_deeplink/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/fluttersdk/magic_deeplink/ci.yml?branch=master&label=CI" alt="CI Status" /></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT" /></a>
  <a href="https://pub.dev/packages/magic_deeplink/score"><img src="https://img.shields.io/pub/points/magic_deeplink" alt="pub points" /></a>
  <a href="https://github.com/fluttersdk/magic_deeplink/stargazers"><img src="https://img.shields.io/github/stars/fluttersdk/magic_deeplink?style=flat" alt="GitHub Stars" /></a>
</p>

<p align="center">
  <a href="https://magic.fluttersdk.com/deeplink">Website</a> ·
  <a href="https://magic.fluttersdk.com/packages/deeplink/getting-started/installation">Docs</a> ·
  <a href="https://pub.dev/packages/magic_deeplink">pub.dev</a> ·
  <a href="https://github.com/fluttersdk/magic_deeplink/issues">Issues</a> ·
  <a href="https://github.com/fluttersdk/magic_deeplink/discussions">Discussions</a>
</p>

---

> **Alpha** — `magic_deeplink` is under active development. APIs may change between minor versions until `1.0.0`.

---

## Why Magic Deeplink?

Setting up deep links in Flutter means dealing with platform-specific manifests, JSON files hosted on your server, parsing URIs in multiple places, and wiring it all together. Every project reinvents the same boilerplate.

**Magic Deeplink** gives you a single, declarative config file. One CLI command generates the server-side files. One service provider boots everything. Handlers follow a clean chain-of-responsibility pattern — the first match wins.

> **Config-driven deep linking.** Define your domain, paths, and platform credentials once. Magic Deeplink handles the rest.

---

## Features

| | Feature | Description |
|---|---------|-------------|
| :link: | **Unified API** | Single interface for handling deep links on iOS and Android |
| :electric_plug: | **Driver Pattern** | Extensible driver architecture — swap `app_links` for any custom driver |
| :traffic_light: | **Route Handler** | Automatically maps deep link paths to Magic Routes |
| :bell: | **OneSignal Integration** | Seamless handling of notification click actions via `magic_notifications` |
| :hammer_and_wrench: | **CLI Tools** | Auto-generate `apple-app-site-association` and `assetlinks.json` |
| :gear: | **Config-Driven** | All settings in one Dart config file — no platform manifest editing |
| :jigsaw: | **Handler Chain** | Register custom handlers with `canHandle` / `handle` — first match wins |
| :package: | **Pure Dart** | No native platform code — platform support via `app_links` package |

---

## Quick Start

### 1. Add the dependency

```yaml
dependencies:
  magic_deeplink: ^0.0.1
```

### 2. Install configuration

```bash
dart run magic_deeplink:install
```

This generates `lib/config/deeplink.dart`, injects `DeeplinkServiceProvider` into `lib/config/app.dart`, and wires the `deeplinkConfig` factory into `lib/main.dart`.

### 3. Boot the provider

The `DeeplinkServiceProvider` is automatically registered during install. On app boot, it:

- Creates the configured driver (`app_links` by default)
- Initializes the driver with your config
- Listens for incoming deep links
- Routes them through your registered handlers

That's it — deep links now work across iOS and Android.

---

## Configuration

After running the install command, edit `lib/config/deeplink.dart`:

```dart
Map<String, dynamic> get deeplinkConfig => {
  'deeplink': {
    'enabled': true,
    'driver': 'app_links',
    'domain': 'example.com',
    'scheme': 'https',
    'ios': {
      'team_id': 'ABC123XYZ',
      'bundle_id': 'com.example.app',
    },
    'android': {
      'package_name': 'com.example.app',
      'sha256_fingerprints': [
        'AA:BB:CC:...',
      ],
    },
    'paths': [
      '/monitors/*',
      '/status-pages/*',
      '/invite/*',
    ],
  },
};
```

All values are read at runtime via `ConfigRepository` — no hardcoded strings scattered across your codebase.

---

## Server-Side Setup

Universal Links (iOS) and App Links (Android) require verification files hosted on your domain.

Generate them with one command:

```bash
dart run magic_deeplink:generate --output ./public
```

This creates two files:

| File | Platform | Purpose |
|------|----------|---------|
| `apple-app-site-association` | iOS | Universal Links verification |
| `assetlinks.json` | Android | App Links verification |

Upload these to the root or `.well-known/` directory of your web server so that `https://example.com/.well-known/apple-app-site-association` and `https://example.com/.well-known/assetlinks.json` are publicly accessible.

---

## CLI Tools

### `install`

Scaffolds the deeplink configuration into your Magic project.

```bash
dart run magic_deeplink:install
```

**What it does:**

- Generates `lib/config/deeplink.dart` config file
- Injects `DeeplinkServiceProvider` into `lib/config/app.dart`
- Injects `deeplinkConfig` factory into `lib/main.dart`

| Flag | Short | Description |
|------|-------|-------------|
| `--force` | `-f` | Overwrite existing configuration file |

### `generate`

Generates platform verification files from your config.

```bash
dart run magic_deeplink:generate --output ./public
```

Reads configuration from `lib/config/deeplink.dart` first. CLI flags override config file values.

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--output` | `-o` | `public` | Output directory for generated files |
| `--root` | | `.` | Project root directory |
| `--team-id` | | — | Apple Developer Team ID |
| `--bundle-id` | | — | iOS app bundle identifier |
| `--package-name` | | — | Android package name |
| `--sha256-fingerprints` | | — | SHA-256 certificate fingerprints (multi) |
| `--paths` | | `['/*']` | Paths to handle (multi) |

---

## Custom Handlers

Register your own handlers for specific deep link patterns:

```dart
class InviteHandler extends DeeplinkHandler {
  @override
  bool canHandle(Uri uri) {
    return uri.path.startsWith('/invite/');
  }

  @override
  Future<bool> handle(Uri uri) async {
    final code = uri.pathSegments.last;
    // Handle invite code...
    return true;
  }
}

// In your AppServiceProvider or main.dart:
DeeplinkManager().registerHandler(InviteHandler());
```

Handlers follow the chain-of-responsibility pattern. The first handler where `canHandle` returns `true` processes the URI. Return `true` from `handle` to indicate success, `false` to pass to the next handler.

---

## Notification Integration

If `magic_notifications` is installed and bound in the container, `magic_deeplink` automatically registers an `OneSignalDeeplinkHandler` that processes notification click actions containing deep link URLs.

No extra configuration needed — the provider detects the binding at boot time and wires everything up.

To send a deep link via OneSignal, add the `url` or `deep_link` field to your notification payload.

---

## Architecture

```
App launch → DeeplinkServiceProvider.boot()
  → reads config via ConfigRepository
  → creates AppLinksDriver
  → driver.initialize(config)
  → listens driver.onLink stream → manager.handleUri()
  → first matching handler wins (canHandle → handle)
  → delays initial link via Future.delayed(Duration.zero) for router readiness
  → optional: OneSignal handler if magic_notifications bound
```

**Key patterns:**

| Pattern | Implementation |
|---------|---------------|
| Singleton Manager | `DeeplinkManager` — central orchestrator |
| Strategy (Driver) | `AppLinksDriver` implements `DeeplinkDriver` contract |
| Chain of Responsibility | Handlers checked in order — first match wins |
| Service Provider | Two-phase bootstrap: `register()` (sync) → `boot()` (async) |
| IoC Container | All bindings via `app.singleton()` / `app.make()` |

---

## Documentation

| Document | Description |
|----------|-------------|
| [Installation](https://magic.fluttersdk.com/packages/deeplink/getting-started/installation) | Adding the package and running the installer |
| [Configuration](https://magic.fluttersdk.com/packages/deeplink/getting-started/configuration) | Config file reference and options |
| [Drivers](https://magic.fluttersdk.com/packages/deeplink/basics/drivers) | Driver contract and `AppLinksDriver` details |
| [Handlers](https://magic.fluttersdk.com/packages/deeplink/basics/handlers) | Built-in handlers and writing custom ones |
| [CLI Tools](https://magic.fluttersdk.com/packages/deeplink/basics/cli) | Install and generate command reference |
| [Deeplink Manager](https://magic.fluttersdk.com/packages/deeplink/architecture/deeplink-manager) | Manager singleton and handler orchestration |
| [Service Provider](https://magic.fluttersdk.com/packages/deeplink/architecture/service-provider) | Bootstrap lifecycle and IoC bindings |

---

## Contributing

Contributions are welcome! Please see the [issues page](https://github.com/fluttersdk/magic_deeplink/issues) for open tasks or to report bugs.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests following the [TDD flow](#) — red, green, refactor
4. Ensure all checks pass: `flutter test`, `dart analyze`, `dart format .`
5. Submit a pull request

---

## License

Magic Deeplink is open-sourced software licensed under the [MIT License](LICENSE).

---

<p align="center">
  Built with care by <a href="https://github.com/fluttersdk">FlutterSDK</a><br/>
  <sub>If Magic Deeplink helps your project, consider giving it a <a href="https://github.com/fluttersdk/magic_deeplink">star on GitHub</a>.</sub>
</p>
