# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.1.2] - 2026-09-21

### Changed

- **Every sibling floor names this batch's release.** `magic` moves `^0.0.14` to `^0.0.15`. The old ranges already admitted the new versions, so a fresh `pub get` resolves nothing differently; what changes is that the floors name the releases this package is verified against. magic 0.0.15 is breaking in its database layer (a migration may no longer manage its own transaction, and `DB.transaction` refuses a callback that closes the transaction itself); nothing in this package calls either, so no code here changes, but an app below magic 0.0.15 no longer resolves this release. (`pubspec.yaml`)

## [0.1.1] - 2026-09-19

### Fixed

- **The `magic` floor names a version this package's own suite can actually run against.** It said `^0.0.5`, and at that version the library still analyzes clean while the test suite does not compile: `MagicApp.register` returns `void` below magic 0.0.8 and `Future<void>` from 0.0.8 on, and the provider tests await it. So the floor was claiming support for three releases nothing here is verified against, which is the kind of claim that only ever fails in somebody else's build. It went to `^0.0.8` first, the lowest version at which `flutter analyze` is clean on `lib/` AND `test/`.

  It ships as `^0.0.14`, which is a different decision on top of that one. The batch this release belongs to pins every sibling to its newest, so the floor now names magic's current release rather than the oldest verified one. That is worth stating plainly because 0.0.14 carries a BREAKING change: an unresolvable route middleware alias stops the app at `Magic.init` instead of leaving the route ungated. A consumer on magic 0.0.8 through 0.0.13 no longer resolves this package, and one moving to it inherits that check.

  `fluttersdk_artisan` goes `^0.0.8` to `^0.0.16` for the same reason. Nothing in `lib/` needed either move, so no behaviour in this package changes. (`pubspec.yaml`)

## [0.1.0] - 2026-09-09

### 💥 Breaking Changes
- **`DeeplinkHandler.handle` and `DeeplinkManager.handleUri` take a required `DeeplinkSource source`.** A handler could not previously tell an OS-opened link, which anyone able to send the device a link can craft, from a push notification's own payload, which the server authored. A consumer that acts on more than the path (switching a team off a `team_id` key carried in the link, say) now has something to check first. `source` is `osLink`, `push`, or `manual`, and is required rather than defaulted so a handler that forgot to ask does not silently treat a crafted link like a trusted one. An optional `Map<String, dynamic>? payload` travels alongside it, carrying the whole push payload on the `push` path and `null` everywhere else; `OneSignalDeeplinkHandler` passes the full payload, the driver subscription in the provider passes none.

### Fixed
- **A push tapped while the app is CLOSED now opens its screen.** Measured on a physical iPhone against a real server-sent notification: the same push opened the right screen when the app was already running and landed on the home screen when it was not. The OneSignal SDK replays the tap that launched the app while it initialises, which is before anything has been drawn and therefore before magic's router can accept a navigation, so the link was handed over, went nowhere, and the app finished booting onto its own initial route. Nothing failed loudly; a cold tap simply opened the app in the wrong place, which reads as the feature working badly rather than as a defect. `OneSignalDeeplinkHandler` now waits for the first frame before routing, taking `WidgetsFlutterBinding.ensureInitialized().endOfFrame` once per `setup` exactly as the OS-link path in `DeeplinkServiceProvider` already did; the two paths had been asymmetric since the push bridge started working in 0.0.3. `endOfFrame` rather than a post-frame callback for the same reason as there: it schedules a frame when the scheduler is idle, so a link handed to an application nobody is drawing is still delivered. A delivery still in flight behind that frame when `dispose` lands is dropped rather than routed into a torn-down consumer.

### Added
- **`deeplink:doctor` command.** `magic_notifications` and `magic_starter` each ship a doctor; this plugin shipped none, and it needed one most. The install has a half no manifest installer can automate (an `<intent-filter>` inside a specific `<activity>`, a `<meta-data>` on the right element), and every way of getting that hand-written half wrong is silent: a deep link simply opens the browser, with no exception and no log line anywhere. The command reads the consumer's `lib/config/deeplink.dart` (reusing `GenerateCommand.parseDeeplinkConfig` rather than a second parser), rejects scaffold placeholders left over from install, and checks both platforms structurally rather than by substring search: it parses the Android manifest's element tree so a `flutter_deeplinking_enabled` meta-data placed on `<application>` instead of `<activity>` is caught, a case a plain `grep` cannot see because both locations contain the identical text. It also validates the `autoVerify` intent-filter's `http`/`https` schemes and host, the iOS entitlements' `applinks:` host, `FlutterDeepLinkingEnabled`, and that the generated `apple-app-site-association`/`assetlinks.json` files agree with the config (warning rather than failing on a legacy+modern AASA format mix, per Apple's TN3155). All checks are local and read-only by default; `--remote` additionally fetches both association files from the live domain to confirm the server agrees with the repo. The report always closes by naming what no local or remote check can prove: that a real device matches the link, since `swcutil verify` needs root and Android verifies at install time.
- **The web build stops carrying an inert `dart:io` import.** `AppLinksDriver` was a single class reaching for `Platform.isAndroid`/`isIOS`/`isMacOS` inside a `try`/`catch`, which only worked at all because `dart:io` happens to resolve (to a stub) under `dart2js`/`dart2wasm`. It is now a conditional-export barrel over three arms: an io arm that still wraps the `app_links` package and answers `isSupported` from the same three platform checks, a web arm, and a stub arm for anything else. Both the web and the stub arm answer every member without touching a platform channel: `isSupported` false, `getInitialLink()` null, `onLink` an empty stream, `initialize` and `dispose` no-ops. The web arm is deliberately inert rather than wired to `app_links_web`: that package reads the boot-time `location.href` once and never reacts to later navigation, and GoRouter already owns the address bar under this app's path url strategy, so routing the same URI twice would be the bug, not the fix.

### Changed
- **`DeeplinkServiceProvider.boot()` now reads `deeplink.enabled`.** `doc/getting-started/configuration.md` has always documented it as the off switch (`Config.get<bool>('deeplink.enabled', true)`), and until now nothing read it: a consumer who set it to `false` still got a driver, a link subscription, and a push bridge wired up. An absent key still means enabled; only an explicit `false` now wires nothing.
- **The driver is only wired when `driver.isSupported`.** Handing an unsupported driver to the manager used to leave `manager.driver` answering with something that could never deliver a link, and would have shipped every browser build carrying a driver for a mechanism the browser does not have. The web and stub arms above make that check meaningful for the first time.
- **A cold-start link is delivered exactly once, not twice.** The provider used to both subscribe to `driver.onLink` and separately call `manager.getInitialLink()`, and on Android the `app_links` package serves the initial link on both paths, so a single tap on a notification or a link ran the whole handler chain twice. `app_links`' own README describes its link stream as carrying "all events (initial link and further)", so the stream is now the one delivery path; `DeeplinkManager.getInitialLink()` stays available for a consumer that wants to ask directly, but the provider no longer calls it.
- **Routing an incoming deep link reports a failure instead of letting it escape.** The provider used to schedule delivery with `Future.delayed(Duration.zero, ...)` and never awaited the result, so a handler that threw (a router not yet built, say) surfaced as an unhandled async error and took the tapped link down with it silently. Delivery now awaits `WidgetsFlutterBinding.ensureInitialized().endOfFrame`, captured once at boot so a slow boot no longer races a fixed timer, and wraps the handoff in a `try`/`catch` that reports at error level through magic's `Log` (guarded by `Magic.bound('log')`) rather than swallowing or escaping.
- **The AASA generator emits Apple's modern `appIDs` + `components` shape.** `buildAppleAppSiteAssociation` used to write the legacy `appID` + `paths` entry; it now writes one `details` entry per Apple's TN3155 format, with no `apps` key, because Apple's own guidance warns that mixing the two schemas can produce unexpected behaviour for universal links. `parseDeeplinkConfig` also now tolerates a Dart generic type annotation before a list literal (`<String>[...]`), which is how a config file typed by hand writes `sha256_fingerprints` and `paths`.

## [0.0.3] - 2026-09-02

### Fixed
- **A tapped push notification now opens its deep link. It never has before.** The OneSignal wiring shipped in 0.0.1 and has been inert in every release since: `DeeplinkServiceProvider.boot()` read the push driver's `onNotificationClicked` and cast it to `Stream<Map<String, dynamic>>`, a type it has never had (`magic_notifications` publishes `Stream<PushNotificationEvent>`), so the cast threw on every boot. It could not have got that far anyway, because the driver is attached in the notifications provider's `boot`, which runs after this one in the order consumers register them, so the read that preceded the cast threw first. Both throws landed in a `catch` whose body was two comment lines, which is why nobody noticed: no log, no exception, just a push that opened the app wherever it happened to be. The package's own test suite certified the feature green with a double whose stream really was a `Stream<Map<String, dynamic>>`, and which handed out a driver before boot.
- **The wiring no longer depends on provider order or on a driver existing.** `OneSignalDeeplinkHandler.setup` now subscribes to the notification manager's own `onPushClicked` stream, which the manager owns from construction and republishes onto whenever a driver is attached, so notifications may boot before or after this package. That stream is also the subject-guarded one, so a push addressed to whoever held the device before does not open a deep link for whoever holds it now. An app without `magic_notifications` installed creates nothing here: no subscription, no timer, no handler.
- **A failure is reported instead of swallowed.** A notification manager that publishes no `onPushClicked`, an event carrying no readable payload, and an error on the click stream are each logged at error level through magic's `Log`, guarded by `Magic.bound('log')` so a host that binds no logger is not handed a second failure on a path that is already degrading. There is no empty `catch` left in this package.
- **Resolving the notifications manager can no longer abort application boot.** `app.make('notifications')` runs the binding factory and `onPushClicked` is a getter, so either can throw; the handler answers `NoSuchMethodError` by name but a `StateError` out of an uninitialised manager is a different thing entirely. magic's `Application.boot` awaits providers in a bare loop with no error handling of its own, so an escaping throw here did not degrade the deep-link feature, it stopped the app booting and took every provider registered after this one with it, over a plugin that is OPTIONAL. The resolution is now guarded and reports at error level through the same seam. This is not the empty `catch` this release removed: that one had two comment lines for a body and is why the feature stayed inert for two years, while this one says what failed and only then lets boot continue.
- **A second `setup` no longer leaves the first subscription live.** The early return for a manager publishing no click stream sat before the cancel, so re-wiring against a manager this handler cannot follow left it routing taps through the previous one.

### Added
- **`DeeplinkServiceProvider.dispose()`, tearing down everything `boot()` wired.** The push-click handler was constructed inline in `boot` and the reference discarded, so the `dispose` that `doc/basics/handlers.md` tells consumers to call in provider teardown was unreachable. The provider now holds the handler it wired, along with the driver's link subscription and the driver itself, and drops all three. Provider-level rather than handler-level on purpose: a `dispose()` reaching only the push handler would read as tearing the provider down while leaving the driver running. It also calls `DeeplinkManager.forgetDriver()`, which existed and had no caller: the manager holds its own reference set by `boot`, so clearing the provider's field alone left the singleton answering `manager.driver` with a driver this provider had just torn down. A `dispose()` that lands INSIDE `boot()` is covered too: `await driver.initialize(...)` suspends, and a teardown in that window used to be followed by boot resuming and subscribing anyway, creating a subscription after the teardown that nothing would ever cancel. And the scheduled initial-link read checks a disposed flag on both sides of its await, because there is no handle to cancel a `Future.delayed` with and a teardown in the same turn as boot would otherwise still route a deep link afterwards. Idempotent, because a consumer calling it does not know which parts a given deployment wired.

### Changed
- **`OneSignalDeeplinkHandler.setup(manager, notifications)` takes the notification manager, not a stream.** The second parameter was `Stream<Map<String, dynamic>>` and is now the `magic_notifications` manager itself, read structurally (`dynamic`) so this package still declares no dependency on that one. `extractData(event)` is new and public: it reads a push event's payload off its `data` member without naming the event's type.

### Runtime requirement
- **The revived wiring reads `NotificationManager.onPushClicked`, which arrives in `magic_notifications` 0.1.0 and does not exist below it.** This package deliberately declares no dependency on `magic_notifications` at all (the coupling is optional; an app can use deep links with no push), so no resolver will ever enforce this version floor. That makes it a requirement only these words can carry: pairing this release with a `magic_notifications` older than 0.1.0 gets the handler's error-level report (`` the bound `notifications` manager ... publishes no `onPushClicked` stream ``) instead of a routed deep link, not a build failure.

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
