# Handlers

- [Introduction](#introduction)
- [The DeeplinkHandler Contract](#the-deeplinkhandler-contract)
    - [canHandle](#canhandle)
    - [handle](#handle)
- [Built-in Handlers](#built-in-handlers)
    - [RouteDeeplinkHandler](#routedeeplinkhandler)
    - [OneSignalDeeplinkHandler](#onesignaldeeplinkhandler)
- [Creating Custom Handlers](#creating-custom-handlers)
- [Registering Handlers](#registering-handlers)
- [Handler Execution Order](#handler-execution-order)

<a name="introduction"></a>
## Introduction

Handlers are the core processing unit of the deep link pipeline. When a deep link arrives, the `DeeplinkManager` walks its registered handler list and delegates the URI to the first handler that claims it. This chain-of-responsibility pattern keeps each handler focused on a single concern and makes the pipeline trivially extensible.

Every handler implements the `DeeplinkHandler` contract. The two built-in handlers — `RouteDeeplinkHandler` and `OneSignalDeeplinkHandler` — cover the most common integration scenarios out of the box.

<a name="the-deeplinkhandler-contract"></a>
## The DeeplinkHandler Contract

All handlers extend the abstract `DeeplinkHandler` class:

```dart
abstract class DeeplinkHandler {
  bool canHandle(Uri uri);
  Future<bool> handle(Uri uri);
}
```

<a name="canhandle"></a>
### canHandle

```dart
bool canHandle(Uri uri);
```

A synchronous predicate. Return `true` if this handler wants to process the URI; `false` to pass it to the next handler in the chain. Keep this method cheap — it runs on every incoming link before any handler is invoked.

<a name="handle"></a>
### handle

```dart
Future<bool> handle(Uri uri);
```

The async processing method, called only when `canHandle` returned `true`. Return `true` if the URI was successfully handled, `false` if processing failed but should not be retried by another handler. **Never throw** from this method — exceptions break the pipeline. Catch internally and return `false` on failure.

<a name="built-in-handlers"></a>
## Built-in Handlers

<a name="routedeeplinkhandler"></a>
### RouteDeeplinkHandler

Matches incoming URI paths against a list of patterns and navigates to the matched route using `MagicRoute.to()`.

**Constructor:**

```dart
RouteDeeplinkHandler({required List<String> paths})
```

**Pattern syntax:**

| Pattern | Matches |
|---------|---------|
| `/products` | Exactly `/products` |
| `/products/*` | Any single path segment after `/products/` |
| `/products/:id` | A single non-slash segment (named parameter) |
| `/shop/*/detail` | Any path with a wildcard middle segment |

Matching is case-insensitive and trailing slashes are normalized before comparison.

**Example:**

```dart
final handler = RouteDeeplinkHandler(
  paths: [
    '/products/:id',
    '/shop/*',
    '/promotions',
  ],
);
```

When a matching URI arrives, the handler calls:

```dart
MagicRoute.to(uri.path, query: uri.queryParameters);
```

Query parameters are forwarded automatically, so `https://example.com/products/42?ref=email` navigates to `/products/42` with `{'ref': 'email'}` available via `Request.query('ref')`.

<a name="onesignaldeeplinkhandler"></a>
### OneSignalDeeplinkHandler

Bridges OneSignal push notification click events into the deep link pipeline. It does **not** implement `DeeplinkHandler` directly — instead it acts as a listener adapter that extracts a URI from the notification payload and feeds it to the manager.

**URI extraction:**

The handler checks the notification `data` map for these keys in order: `url`, `deep_link`, `link`, `uri`. The first non-empty string value that parses as a valid URI is used.

**Setup:**

```dart
void setup(DeeplinkManager manager, Stream<Map<String, dynamic>> notificationStream)
```

Call `setup()` once, passing the manager singleton and a stream of notification data maps (typically sourced from your `magic_notifications` integration). The handler subscribes internally and routes every matched URI through `manager.handleUri()`.

**Disposal:**

```dart
void dispose()
```

Cancels the internal stream subscription. Call this in your service provider's teardown or when the handler is no longer needed.

**Example:**

```dart
final onesignalHandler = OneSignalDeeplinkHandler();

// Inside DeeplinkServiceProvider.boot():
onesignalHandler.setup(
  DeeplinkManager(),
  notificationClickStream, // Stream<Map<String, dynamic>>
);
```

<a name="creating-custom-handlers"></a>
## Creating Custom Handlers

Extend `DeeplinkHandler` to handle any URI matching logic your application requires.

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

class ProductDeeplinkHandler extends DeeplinkHandler {
  @override
  bool canHandle(Uri uri) {
    // Only claim URIs with the /products path and a numeric id segment
    final segments = uri.pathSegments;
    return segments.length == 2 &&
        segments[0] == 'products' &&
        int.tryParse(segments[1]) != null;
  }

  @override
  Future<bool> handle(Uri uri) async {
    final id = int.parse(uri.pathSegments[1]);

    try {
      final product = await ProductRepository.find(id);

      if (product == null) {
        MagicRoute.to('/products/not-found');
        return false;
      }

      MagicRoute.to('/products/$id', query: uri.queryParameters);
      return true;
    } catch (_) {
      return false;
    }
  }
}
```

Key rules when implementing a custom handler:

- `canHandle` must be **synchronous** and **side-effect free**.
- `handle` must **never throw** — wrap async operations in try-catch.
- Return `false` (not throw) when the URI cannot be handled after `canHandle` returned `true`.

<a name="registering-handlers"></a>
## Registering Handlers

Register handlers on the `DeeplinkManager` singleton via `registerHandler()`. The manager deduplicates registrations — adding the same instance twice has no effect.

```dart
final manager = DeeplinkManager();

manager.registerHandler(
  RouteDeeplinkHandler(paths: ['/products/:id', '/shop/*']),
);

manager.registerHandler(ProductDeeplinkHandler());
```

The recommended place to register handlers is inside `DeeplinkServiceProvider.boot()`, after the driver is initialized:

```dart
class DeeplinkServiceProvider extends ServiceProvider {
  @override
  Future<void> boot() async {
    final manager = app.make<DeeplinkManager>('deeplink');

    manager.registerHandler(
      RouteDeeplinkHandler(
        paths: app.make<ConfigRepository>('config').get('deeplink.paths'),
      ),
    );

    manager.registerHandler(ProductDeeplinkHandler());
  }
}
```

<a name="handler-execution-order"></a>
## Handler Execution Order

Handlers are evaluated in **registration order**. The manager iterates the list and stops at the first handler whose `canHandle` returns `true`:

```dart
Future<bool> handleUri(Uri uri) async {
  for (final handler in _handlers) {
    if (handler.canHandle(uri)) {
      return await handler.handle(uri);
    }
  }
  return false; // No handler claimed the URI
}
```

Practical implications:

- **Register specific handlers before generic ones.** A `RouteDeeplinkHandler` with a wildcard pattern (`/products/*`) will consume URIs before a more specific custom handler if registered first.
- **The manager returns `false`** when no handler claims a URI. Consider registering a catch-all fallback handler last if you want to log or report unhandled links.
- **`handleUri` also emits to `manager.onLink`** before the handler chain runs, so stream listeners always receive every URI regardless of whether a handler claims it.

```dart
// Specific handler first
manager.registerHandler(ProductDeeplinkHandler());

// Generic route handler second — won't shadow the specific one
manager.registerHandler(
  RouteDeeplinkHandler(paths: ['/products/*', '/shop/*']),
);
```
