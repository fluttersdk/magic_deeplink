# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed
- **A tapped push notification now opens its deep link. It never has before.** The OneSignal wiring shipped in 0.0.1 and has been inert in every release since: `DeeplinkServiceProvider.boot()` read the push driver's `onNotificationClicked` and cast it to `Stream<Map<String, dynamic>>`, a type it has never had (`magic_notifications` publishes `Stream<PushNotificationEvent>`), so the cast threw on every boot. It could not have got that far anyway, because the driver is attached in the notifications provider's `boot`, which runs after this one in the order consumers register them, so the read that preceded the cast threw first. Both throws landed in a `catch` whose body was two comment lines, which is why nobody noticed: no log, no exception, just a push that opened the app wherever it happened to be. The package's own test suite certified the feature green with a double whose stream really was a `Stream<Map<String, dynamic>>`, and which handed out a driver before boot.
- **The wiring no longer depends on provider order or on a driver existing.** `OneSignalDeeplinkHandler.setup` now subscribes to the notification manager's own `onPushClicked` stream, which the manager owns from construction and republishes onto whenever a driver is attached, so notifications may boot before or after this package. That stream is also the subject-guarded one, so a push addressed to whoever held the device before does not open a deep link for whoever holds it now. An app without `magic_notifications` installed creates nothing here: no subscription, no timer, no handler.
- **A failure is reported instead of swallowed.** A notification manager that publishes no `onPushClicked`, an event carrying no readable payload, and an error on the click stream are each logged at error level through magic's `Log`, guarded by `Magic.bound('log')` so a host that binds no logger is not handed a second failure on a path that is already degrading. There is no empty `catch` left in this package.
- **Resolving the notifications manager can no longer abort application boot.** `app.make('notifications')` runs the binding factory and `onPushClicked` is a getter, so either can throw; the handler answers `NoSuchMethodError` by name but a `StateError` out of an uninitialised manager is a different thing entirely. magic's `Application.boot` awaits providers in a bare loop with no error handling of its own, so an escaping throw here did not degrade the deep-link feature, it stopped the app booting and took every provider registered after this one with it, over a plugin that is OPTIONAL. The resolution is now guarded and reports at error level through the same seam. This is not the empty `catch` this release removed: that one had two comment lines for a body and is why the feature stayed inert for two years, while this one says what failed and only then lets boot continue.
- **A second `setup` no longer leaves the first subscription live.** The early return for a manager publishing no click stream sat before the cancel, so re-wiring against a manager this handler cannot follow left it routing taps through the previous one.

### Added
- **`DeeplinkServiceProvider.dispose()`.** The push-click handler was constructed inline in `boot` and the reference discarded, so the `dispose` that `doc/basics/handlers.md` tells consumers to call in provider teardown was unreachable. The provider now holds the handler it wired and tears it down.

### Changed
- **`OneSignalDeeplinkHandler.setup(manager, notifications)` takes the notification manager, not a stream.** The second parameter was `Stream<Map<String, dynamic>>` and is now the `magic_notifications` manager itself, read structurally (`dynamic`) so this package still declares no dependency on that one. `extractData(event)` is new and public: it reads a push event's payload off its `data` member without naming the event's type.

### Runtime requirement
- **The revived wiring reads `NotificationManager.onPushClicked`, which does not exist in the currently published `magic_notifications` 0.0.3; it arrives in 0.1.0, not yet released.** This package deliberately declares no dependency on `magic_notifications` at all (the coupling is optional; an app can use deep links with no push), so no resolver will ever enforce this version floor. That makes it a requirement only these words can carry: pairing this release with a `magic_notifications` older than 0.1.0 gets the handler's error-level report (`` the bound `notifications` manager ... publishes no `onPushClicked` stream ``) instead of a routed deep link, not a build failure.

## [0.0.2] - 2026-07-26

### Changed
- **`magic` constraint bumped to `^0.0.3` -> `^0.0.5`.** The old bound excluded every magic release since 0.0.4: under pub's `0.0.z` caret semantics `^0.0.3` means `<0.0.4`, so this plugin could not resolve alongside a consumer on current magic at all. Now tracks magic 0.0.5. No behavior change in this package.

## [0.0.1] - 2026-06-24

### 💥 Breaking Changes
- **Removed bin/ entrypoint**: `dart run magic_deeplink:install` / `dart run magic_deeplink:generate` no longer available. Use host-dispatched artisan commands instead: `dart run <app>:artisan deeplink:install` and `dart run <app>:artisan deeplink:generate`. This requires adding `MagicDeeplinkArtisanProvider` to your app's artisan providers list (see CLAUDE.md for setup).
- **Removed magic_cli dependency**: Commands now extend `ArtisanCommand` from `fluttersdk_artisan` instead of `Command` from `magic_cli`.

### ✨ Improvements
- **Manifest-driven install**: The `deeplink:install` command is now powered by `install.yaml` and the artisan transactional installer, replacing imperative setup code. This enables consistent scaffolding across all magic plugins.
- **Read-only MCP tools**: none. magic_deeplink ships only mutating commands (install, generate) and registers no MCP tools.

### 📚 Documentation
- **README**: Rewrite to match Magic ecosystem format (centered logo, badges, features table, quick start)
- **doc/ folder**: Add comprehensive documentation (installation, configuration, drivers, handlers, CLI, architecture)
- **CLAUDE.md**: Updated architecture section and command table to reflect artisan dispatch model

### 🔧 Improvements
- **Package naming**: Fix `fluttersdk_magic_deeplink` → `magic_deeplink` references for pub.dev publishing

## [0.0.1-alpha.1] - 2026-03-25

### ✨ Core Features
- **Unified Deep Link API**: Single interface for iOS Universal Links and Android App Links
- **Driver Pattern**: Extensible driver architecture with `AppLinksDriver` as default
- **Route Handler**: Automatically maps deep link paths to Magic Routes via `RouteDeeplinkHandler`
- **OneSignal Integration**: Seamless notification click → deep link handling via `OneSignalDeeplinkHandler`
- **CLI Tools**: `install` command generates config, `generate` command produces `apple-app-site-association` and `assetlinks.json`
- **Service Provider**: `DeeplinkServiceProvider` for automatic DI registration and boot
