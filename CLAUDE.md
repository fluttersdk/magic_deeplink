# Magic Deeplink Plugin

Flutter deep linking plugin for the Magic Framework. Universal Links (iOS) + App Links (Android) via `app_links` package.

**Version:** 0.0.1 · **Dart:** >=3.6.0 · **Flutter:** >=3.27.0

## Commands

| Command | Description |
|---------|-------------|
| `flutter test --coverage` | Run all tests with coverage |
| `flutter analyze --no-fatal-infos` | Static analysis |
| `dart format .` | Format all code |
| `dart run magic_deeplink:install` | Generate `lib/config/deeplink.dart` in consumer project |
| `dart run magic_deeplink:generate --output ./public` | Generate apple-app-site-association & assetlinks.json |

## Architecture

**Pattern**: ServiceProvider + Singleton Manager + Driver/Handler chain

```
lib/
├── magic_deeplink.dart       # Barrel export (Core, Handlers, Drivers, Providers, Exceptions)
└── src/
    ├── deeplink_manager.dart  # Singleton manager — driver + handler orchestration
    ├── drivers/               # Platform abstraction (AppLinksDriver)
    ├── handlers/              # URI handlers (RouteDeeplinkHandler, OneSignalDeeplinkHandler)
    ├── providers/             # DeeplinkServiceProvider (register + boot)
    ├── exceptions/            # DeeplinkException
    └── cli/                   # Install + Generate commands (magic_cli integration)
bin/
└── magic_deeplink.dart        # CLI entry point — registers commands with Kernel
assets/stubs/                  # Stub templates for code generation
```

**Data flow:** App launch → `DeeplinkServiceProvider.boot()` → creates driver → listens `onLink` stream → `manager.handleUri()` → first matching handler wins

**Pure Dart** — no android/, ios/, or native platform code. Platform support via `app_links` package.

## Post-Change Checklist

After ANY source code change, sync **before committing**:

1. **`CHANGELOG.md`** — Add entry under `[Unreleased]` section
2. **`README.md`** — Update if features, API, or usage changes
3. **`doc/`** — Update relevant documentation files

## Development Flow (TDD)

Every feature, fix, or refactor must go through the red-green-refactor cycle:

1. **Red** — Write a failing test that describes the expected behavior
2. **Green** — Write the minimum code to make the test pass
3. **Refactor** — Clean up while keeping tests green

**Rules:**
- No production code without a failing test first
- Run `flutter test` after every change — all tests must stay green
- Run `dart analyze` after every change — zero warnings, zero errors
- Run `dart format .` before committing — zero formatting issues

**Verification cycle:** Edit → `flutter test` → `dart analyze` → repeat until green

## Testing

- Mock via contract inheritance (no mockito): `class MockDeeplinkDriver extends DeeplinkDriver`
- Reset state in setUp: `manager.forgetHandlers()`, `manager.forgetDriver()`
- Tests mirror `lib/src/` structure in `test/`
- CLI tests in `test/cli/commands/`

## Key Gotchas

| Mistake | Fix |
|---------|-----|
| Hardcoded config values | Read from `ConfigRepository`: `config.get('deeplink.driver')` |
| Direct manager instantiation | Use singleton factory: `DeeplinkManager()` |
| Tight coupling to magic_notifications | Check `app.bound('notifications')` + dynamic cast + try-catch |
| Handler throws instead of returning bool | Handlers return `Future<bool>`, never throw |
| Forgetting async in boot phase | Driver init, stream setup, initial link fetch — all async |
| Deferred work for UI context | Use `Future.delayed(Duration.zero, ...)` for post-frame work |
| Missing stream disposal | `StreamController` should be disposed in provider teardown |

## Skills & Extensions

- `fluttersdk:magic-framework` — Magic Framework patterns: facades, service providers, IoC, Eloquent ORM, controllers, routing. Use for ANY code touching Magic APIs.

## CI

- `ci.yml`: push/PR → `flutter pub get` → `flutter analyze --no-fatal-infos` → `dart format --set-exit-if-changed` → `flutter test --coverage` → codecov upload
