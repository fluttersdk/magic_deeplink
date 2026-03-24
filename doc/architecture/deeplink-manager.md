# DeeplinkManager

- [Introduction](#introduction)
- [Singleton Pattern](#singleton-pattern)
- [Driver Orchestration](#driver-orchestration)
    - [Setting a Driver](#setting-a-driver)
    - [Removing a Driver](#removing-a-driver)
    - [Driver Contract](#driver-contract)
- [Handler Chain](#handler-chain)
    - [Registering Handlers](#registering-handlers)
    - [Removing Handlers](#removing-handlers)
    - [Handler Contract](#handler-contract)
- [URI Stream](#uri-stream)
- [handleUri Flow](#handleuri-flow)
- [Initial Link Caching](#initial-link-caching)
- [Data Flow](#data-flow)
- [Related](#related)

<a name="introduction"></a>
## Introduction

`DeeplinkManager` is the central coordinator of the magic_deeplink plugin. It owns a single platform driver, an ordered list of URI handlers, and a broadcast stream that emits every incoming deep link. The `DeeplinkServiceProvider` creates and wires the manager during app boot — consuming code rarely needs to interact with it directly.

```dart
// Resolve the singleton anywhere
final manager = DeeplinkManager();

// Listen to all incoming deep links
manager.onLink.listen((uri) {
  print('Received: $uri');
});
```

<a name="singleton-pattern"></a>
## Singleton Pattern

`DeeplinkManager` enforces a process-wide singleton via a private named constructor and a static final field:

```dart
class DeeplinkManager {
  static final DeeplinkManager _instance = DeeplinkManager._internal();

  factory DeeplinkManager() => _instance;

  DeeplinkManager._internal();
}
```

Every call to `DeeplinkManager()` returns the same `_instance`. There is no public constructor that creates a new object.

**Testing reset:** Because the singleton persists across tests, each `setUp` must clear mutable state before asserting:

```dart
setUp(() {
  manager.forgetHandlers();
  manager.forgetDriver();
});
```

<a name="driver-orchestration"></a>
## Driver Orchestration

The manager delegates all platform I/O to a single `DeeplinkDriver`. The driver is not set at construction time — it is injected by `DeeplinkServiceProvider.boot()` after the IoC container is ready.

<a name="setting-a-driver"></a>
### Setting a Driver

```dart
void setDriver(DeeplinkDriver driver)
```

Assigns the active driver. Replaces any previously set driver without disposing it — the provider is responsible for driver lifecycle.

```dart
manager.setDriver(AppLinksDriver());
```

<a name="removing-a-driver"></a>
### Removing a Driver

```dart
void forgetDriver()
```

Sets `_driver` to `null`. Subsequent calls to `driver` (the getter) will throw a `DeeplinkException` with code `NO_DRIVER` until a new driver is set.

```dart
DeeplinkDriver get driver {
  if (_driver == null) {
    throw DeeplinkException(
      'No deep link driver configured. Make sure to call setDriver() or register the service provider.',
      code: 'NO_DRIVER',
    );
  }
  return _driver!;
}
```

<a name="driver-contract"></a>
### Driver Contract

```dart
abstract class DeeplinkDriver {
  String get name;
  bool get isSupported;
  Future<void> initialize(Map<String, dynamic> config);
  Future<Uri?> getInitialLink();
  Stream<Uri> get onLink;
  void dispose();
}
```

The provider calls `initialize()` once during boot, then subscribes to `onLink` and pipes each emitted URI into `manager.handleUri()`.

<a name="handler-chain"></a>
## Handler Chain

The manager maintains an ordered `List<DeeplinkHandler>`. When a URI arrives, the list is iterated in insertion order and the first handler whose `canHandle()` returns `true` wins — subsequent handlers are skipped.

<a name="registering-handlers"></a>
### Registering Handlers

```dart
void registerHandler(DeeplinkHandler handler)
```

Appends the handler if it is not already in the list (identity check via `List.contains`). Duplicate registrations are silently ignored.

```dart
manager.registerHandler(RouteDeeplinkHandler());
manager.registerHandler(OneSignalDeeplinkHandler());
```

**Checking presence:**

```dart
bool hasHandler(DeeplinkHandler handler)
```

Returns `true` if the exact handler instance is registered.

<a name="removing-handlers"></a>
### Removing Handlers

```dart
void forgetHandlers()
```

Clears the entire handler list. Used in test teardown and provider re-boot scenarios.

<a name="handler-contract"></a>
### Handler Contract

```dart
abstract class DeeplinkHandler {
  bool canHandle(Uri uri);
  Future<bool> handle(Uri uri);
}
```

`canHandle` is synchronous — it inspects the URI and returns a boolean with no side effects. `handle` performs the actual work and returns `true` on success. Handlers must never throw; they return `false` on failure.

<a name="uri-stream"></a>
## URI Stream

```dart
final StreamController<Uri> _linkController = StreamController<Uri>.broadcast();

Stream<Uri> get onLink => _linkController.stream;
```

A `broadcast` controller is used so multiple listeners (e.g., analytics, routing, tests) can subscribe independently without coordinating. The stream is never closed during normal app operation — it lives for the full process lifetime alongside the singleton.

Listening:

```dart
manager.onLink.listen((uri) {
  // Called for every URI that passes through handleUri()
});
```

<a name="handleuri-flow"></a>
## handleUri Flow

```dart
Future<bool> handleUri(Uri uri) async {
  _linkController.add(uri);
  for (final handler in _handlers) {
    if (handler.canHandle(uri)) {
      return await handler.handle(uri);
    }
  }
  return false;
}
```

The method does two things unconditionally and sequentially:

1. **Emit** — the URI is added to `_linkController` before any handler runs. Every stream subscriber receives the URI regardless of whether a handler exists.
2. **Dispatch** — the handler list is iterated in order. The first handler for which `canHandle(uri)` is `true` is invoked. If it succeeds, `true` is returned and iteration stops. If no handler matches, `false` is returned.

The stream emission is intentionally first so that observers see all URIs, not only those that are handled.

<a name="initial-link-caching"></a>
## Initial Link Caching

When an app is launched by tapping a deep link, the link is available via `getInitialLink()`. The manager caches the result after the first driver call so repeated calls are cheap and deterministic:

```dart
Future<Uri?> getInitialLink() async {
  if (_initialLinkFetched) {
    return _initialLink;
  }

  _initialLink = await driver.getInitialLink();
  _initialLinkFetched = true;
  return _initialLink;
}
```

| State | Behavior |
|-------|----------|
| First call (`_initialLinkFetched == false`) | Delegates to `driver.getInitialLink()`, stores result, sets flag |
| Subsequent calls (`_initialLinkFetched == true`) | Returns cached `_initialLink` immediately, no driver call |

`_initialLink` may be `null` if the app was launched normally (not via a deep link). The `null` result is cached just like a non-null URI — the flag is set either way.

**Testing implication:** `forgetDriver()` does not reset `_initialLinkFetched`. If a test exercises initial link caching, it must interact with the singleton before the flag is set, or use a fresh manager instance via the private constructor in test subclasses.

<a name="data-flow"></a>
## Data Flow

```
App launch
    │
    ▼
DeeplinkServiceProvider.boot()
    │
    ├─ manager.setDriver(AppLinksDriver())
    │
    ├─ driver.initialize(config)
    │
    ├─ driver.onLink.listen(manager.handleUri)   ◄─── ongoing links
    │
    └─ manager.getInitialLink()
            │
            ▼
        driver.getInitialLink()          (first call only)
            │
            ▼
        manager.handleUri(uri)
                │
                ├─ _linkController.add(uri)      ──► onLink stream subscribers
                │
                └─ iterate _handlers in order
                        │
                        ├─ handler.canHandle(uri) == false  ──► next handler
                        │
                        └─ handler.canHandle(uri) == true
                                │
                                ▼
                            handler.handle(uri)
                                │
                                └─ return bool  ──► handleUri returns
```

<a name="related"></a>
## Related

- `lib/src/deeplink_manager.dart` — full source
- `lib/src/drivers/deeplink_driver.dart` — driver contract
- `lib/src/handlers/deeplink_handler.dart` — handler contract
- `lib/src/providers/deeplink_service_provider.dart` — wires manager during app boot
- `lib/src/exceptions/deeplink_exception.dart` — `DeeplinkException` with `NO_DRIVER` code
