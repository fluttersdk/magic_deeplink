---
path: "lib/**/*.dart"
---

# Flutter / Dart Stack

- Dart >=3.6.0, Flutter >=3.27.0 — use modern patterns (records, switch expressions, strict null safety)
- Import order: dart/flutter stdlib → third-party packages → `package:magic/magic.dart` → `package:magic_deeplink/...` → relative imports
- Naming: `{Concept}Manager` (singleton), `{Concept}Driver` (strategy impl), `{Purpose}Handler` (chain-of-resp), `{Concept}ServiceProvider` (bootstrap), `{Concept}Exception`
- Singleton pattern: `static final _instance = Class._internal(); factory Class() => _instance;`
- Contract-first: abstract class defines API (`DeeplinkDriver`, `DeeplinkHandler`). Implementations in subdirectories
- Two-phase bootstrap: `register()` binds singletons to IoC (sync), `boot()` configures them (`Future<void>`)
- IoC binding: `app.singleton('key', () => Service())` in register, `app.make<T>('key')` in boot
- Config access: always via `ConfigRepository` — `config.get('deeplink.driver')`, never hardcode
- Optional dependencies: check `app.bound('key')` + dynamic cast + try-catch. Never import optional packages directly
- Handler chain: `canHandle(Uri) → bool`, `handle(Uri) → Future<bool>`. First match wins, return bool (never throw)
- Driver contract: `name`, `isSupported`, `onLink` (Stream), `initialize(Map config)`, `getInitialLink()`, `dispose()`
- Streams: `StreamController<Uri>.broadcast()` for multi-listener events
- Deferred UI work: `Future.delayed(Duration.zero, ...)` to wait for post-frame (router ready)
- Barrel export: `lib/magic_deeplink.dart` groups by concern (Core, Handlers, Drivers, Providers, Exceptions)
- `analysis_options.yaml` uses `package:flutter_lints/flutter.yaml` — zero warnings required
