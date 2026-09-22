# Magic Deeplink Plugin

Flutter deep linking plugin for the Magic Framework. Universal Links (iOS) + App Links (Android) via `app_links` package.

**Version:** 0.1.3 · **Dart:** >=3.6.0 · **Flutter:** >=3.27.0

## Commands

**Host-dispatched via artisan.** Add `MagicDeeplinkArtisanProvider` to your app's artisan providers:

```dart
// lib/config/artisan.dart
import 'package:magic_deeplink/src/cli/deeplink_artisan_provider.dart';

List<ArtisanServiceProvider> get artisanProviders => [
  MagicDeeplinkArtisanProvider(),
  // ... other providers
];
```

Then run:

| Command | Description |
|---------|-------------|
| `flutter test --coverage` | Run all tests with coverage |
| `flutter analyze --no-fatal-infos` | Static analysis |
| `dart format .` | Format all code |
| `dart run <app>:artisan deeplink:install` | Generate `lib/config/deeplink.dart` in consumer project |
| `dart run <app>:artisan deeplink:generate --output ./public` | Generate apple-app-site-association & assetlinks.json |
| `dart run <app>:artisan deeplink:doctor` | Check the install; `--remote` also fetches both association files from the live domain |

## Architecture

**Pattern**: ServiceProvider + Singleton Manager + Driver/Handler chain

```
lib/
├── magic_deeplink.dart       # Barrel export (Core, Handlers, Drivers, Providers, Exceptions)
└── src/
    ├── deeplink_manager.dart  # Singleton manager: driver + handler orchestration
    ├── drivers/               # Platform abstraction (AppLinksDriver)
    ├── handlers/              # URI handlers (RouteDeeplinkHandler, OneSignalDeeplinkHandler)
    ├── providers/             # DeeplinkServiceProvider (register + boot)
    ├── exceptions/            # DeeplinkException
    └── cli/                   # Install + Generate commands
        ├── deeplink_artisan_provider.dart  # ArtisanServiceProvider (no bin entrypoint)
        ├── commands/
        │   ├── install_command.dart        # extends ArtisanInstallCommand, driven by install.yaml
        │   ├── generate_command.dart       # extends ArtisanCommand
        │   └── doctor_command.dart         # reads the config + both platform trees; --remote adds the live host
        └── cli.dart                        # Barrel export (provider + commands)
install.yaml                   # Plugin manifest: config publish, provider/factory injection
assets/stubs/                  # Stub templates for code generation
```

**CLI architecture**: Commands are registered via `MagicDeeplinkArtisanProvider.commands()` (extends `ArtisanServiceProvider`). No bin/ entrypoint: the host app's `artisan.dart` CLI dispatch handles command routing. The `InstallCommand` extends `ArtisanInstallCommand` and is manifest-driven: `install.yaml` specifies what config files to publish and which service provider to inject; the command executes the manifest through the artisan transactional installer.

**Data flow:** App launch → `DeeplinkServiceProvider.boot()` → returns early if `deeplink.enabled == false` → creates driver when `driver.isSupported` → listens `onLink` stream → delivers after `endOfFrame` via `manager.handleUri(uri, source: ...)` → first matching handler wins

**No native Dart plugin code**: `drivers/app_links_driver.dart` is a conditional-export barrel over an io arm (wraps `app_links`), a web arm (explicit no-op: GoRouter already owns the browser address bar), and a stub arm for anything else. The CONSUMER app still needs native setup this package cannot automate beyond one `install.yaml` plist key: an iOS associated-domains entitlement, an Android autoVerify intent filter, and the platform switches that keep Flutter's own deep link handler out of the way. See `doc/getting-started/installation.md#platform-setup`.

## Post-Change Checklist

After ANY source code change, sync **before committing**:

1. **`CHANGELOG.md`**: Add entry under `[Unreleased]` section
2. **`README.md`**: Update if features, API, or usage changes
3. **`doc/`**: Update relevant documentation files

## Development Flow (TDD)

Every feature, fix, or refactor must go through the red-green-refactor cycle:

1. **Red**: Write a failing test that describes the expected behavior
2. **Green**: Write the minimum code to make the test pass
3. **Refactor**: Clean up while keeping tests green

**Rules:**
- No production code without a failing test first
- Run `flutter test` after every change: all tests must stay green
- Run `dart analyze` after every change: zero warnings, zero errors
- Run `dart format .` before committing: zero formatting issues

**Verification cycle:** Edit → `flutter test` → `dart analyze` → repeat until green

## Testing

- Mock via contract inheritance (no mockito): `class MockDeeplinkDriver extends DeeplinkDriver`
- Reset state in setUp: `manager.reset()` (`@visibleForTesting`; clears handlers, driver, the cached initial link, and the `onLink` broadcast controller)
- Tests mirror `lib/src/` structure in `test/`
- CLI tests in `test/cli/commands/`

## Key Gotchas

| Mistake | Fix |
|---------|-----|
| Hardcoded config values | Read from `ConfigRepository`: `config.get('deeplink.driver')` |
| Direct manager instantiation | Use singleton factory: `DeeplinkManager()` |
| Tight coupling to magic_notifications | Check `app.bound('notifications')` + dynamic cast + try-catch |
| Handler throws instead of returning bool | Handlers return `Future<bool>`, never throw |
| Forgetting `source`/`payload` on a handler override | `handle(uri, {required DeeplinkSource source, Map<String, dynamic>? payload})`; only trust `payload` when `source == DeeplinkSource.push` |
| Forgetting async in boot phase | Driver init and stream setup are async |
| Deferred work for UI context | Await `WidgetsFlutterBinding.ensureInitialized().endOfFrame`, not `Future.delayed(Duration.zero, ...)` |
| Missing stream disposal | `DeeplinkServiceProvider.dispose()` tears down the link subscription, the driver, and the push handler; call it in provider teardown |
| Relative paths in `pubspec_overrides.yaml` | Use ABSOLUTE ones. `.worktreeinclude` copies that file into worktrees under `.claude/worktrees/<slug>`, where `../magic` resolves to `.claude/worktrees/magic` and version solving fails on the first path dependency |

## Skills & Extensions

- `fluttersdk:magic-framework`: Magic Framework patterns: facades, service providers, IoC, Eloquent ORM, controllers, routing. Use for ANY code touching Magic APIs.

## CI

- `ci.yml`: push/PR → `flutter pub get` → `flutter analyze --no-fatal-infos` → `dart format --set-exit-if-changed` → `flutter test --coverage` → codecov upload
