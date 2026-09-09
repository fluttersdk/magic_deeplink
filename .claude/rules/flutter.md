---
paths:
  - "lib/**/*.dart"
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
- Handler chain: `canHandle(Uri) → bool`, `handle(Uri, {required DeeplinkSource source, Map<String, dynamic>? payload}) → Future<bool>`. First match wins, return bool (never throw). `source` is REQUIRED rather than defaulted, so a handler that acts on more than the path cannot silently treat a crafted OS link like a server-authored push payload
- Driver contract: `name`, `isSupported`, `onLink` (Stream), `initialize(Map config)`, `getInitialLink()`, `dispose()`
- Streams: `StreamController<Uri>.broadcast()` for multi-listener events
- Waiting for the router: `await WidgetsFlutterBinding.ensureInitialized().endOfFrame`, captured ONCE and awaited, never `Future.delayed(Duration.zero, ...)`. A zero-duration timer is a guess about how long a boot takes and loses the link on any boot slower than it; `endOfFrame` is the event, and it schedules a frame when the scheduler is idle so an application nobody is drawing still gets the link
- Barrel export: `lib/magic_deeplink.dart` groups by concern (Core, Handlers, Drivers, Providers, Exceptions)
- `analysis_options.yaml` uses `package:flutter_lints/flutter.yaml` — zero warnings required
