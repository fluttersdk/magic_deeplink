# Magic Deeplink Plugin

Universal Links (iOS) and App Links (Android) support for Magic Framework applications.

## Features

- 🔗 **Unified API**: Single interface for handling deep links on iOS and Android
- 🔌 **Driver Pattern**: Extensible driver architecture (defaults to `app_links`)
- 🚦 **Route Handler**: Automatically maps deep link paths to Magic Routes
- 🔔 **OneSignal Integration**: seamless handling of notification click actions
- 🛠 **CLI Tools**: Auto-generate `apple-app-site-association` and `assetlinks.json`

## Installation

1. Add the plugin to your `pubspec.yaml`:

```yaml
dependencies:
  fluttersdk_magic_deeplink:
    path: plugins/fluttersdk_magic_deeplink
```

2. Run the install command to generate configuration:

```bash
dart run fluttersdk_magic_deeplink:install
```

This will create `lib/config/deeplink.dart`.

## Configuration

Configure your domain, scheme, and paths in `lib/config/deeplink.dart`:

```dart
Map<String, dynamic> get deeplinkConfig => {
  'deeplink': {
    'enabled': true,
    'driver': 'app_links',
    'domain': 'example.com',
    'scheme': 'https',

    // iOS Configuration
    'ios': {
      'team_id': 'ABC123XYZ',
      'bundle_id': 'com.example.app',
    },

    // Android Configuration
    'android': {
      'package_name': 'com.example.app',
      'sha256_fingerprints': [
        'AA:BB:CC...',
      ],
    },

    // Paths to handle automatically
    'paths': [
      '/monitors/*',
      '/status-pages/*',
      '/invite/*',
    ],
  },
};
```

## Server-Side Configuration

Universal Links and App Links require a file to be hosted on your web server.

Generate these files using the CLI:

```bash
dart run fluttersdk_magic_deeplink:generate --output ./public
```

This will generate:
- `apple-app-site-association` (iOS)
- `assetlinks.json` (Android)

Upload these to the root or `.well-known/` directory of your website.

## Usage

### Automatic Routing

If you use `RouteDeeplinkHandler` (enabled by default), paths defined in your config will automatically navigate to the corresponding Magic Route.

Example:
- Config path: `/monitors/*`
- Deep link: `https://example.com/monitors/123`
- Magic Route: `MagicRoute.to('/monitors/123')`

### Custom Handlers

You can register custom handlers for specific logic:

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

### Notification Integration

The plugin automatically detects if `fluttersdk_magic_notifications` is present and sets up a handler for notification clicks.

To send a deep link via OneSignal, add the `url` (or `deep_link`) field to your notification payload.
