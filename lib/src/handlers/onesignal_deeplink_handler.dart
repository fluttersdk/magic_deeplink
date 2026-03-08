import 'dart:async';
import '../deeplink_manager.dart';

class OneSignalDeeplinkHandler {
  StreamSubscription? _subscription;

  /// Extract URI from OneSignal notification data
  ///
  /// Checks for common keys: 'url', 'deep_link', 'link', 'uri'
  Uri? extractUri(Map<String, dynamic>? data) {
    if (data == null) return null;

    final keys = ['url', 'deep_link', 'link', 'uri'];

    for (final key in keys) {
      if (data.containsKey(key)) {
        final value = data[key];
        if (value is String && value.isNotEmpty) {
          return Uri.tryParse(value);
        }
      }
    }

    return null;
  }

  /// Setup the listener for notification clicks
  void setup(DeeplinkManager manager,
      Stream<Map<String, dynamic>> notificationStream) {
    _subscription?.cancel();
    _subscription = notificationStream.listen((data) {
      final uri = extractUri(data);
      if (uri != null) {
        manager.handleUri(uri);
      }
    });
  }

  /// Dispose the subscription
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
