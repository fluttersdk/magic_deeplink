import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_deeplink/src/deeplink_manager.dart';
import 'package:magic_deeplink/src/handlers/onesignal_deeplink_handler.dart';

/// A push click event shaped like `magic_notifications`' `PushNotificationEvent`.
class FakePushNotificationEvent {
  /// The notification payload, carrying the server's own keys flat.
  final Map<String, dynamic> data;

  /// Creates an event carrying [data].
  const FakePushNotificationEvent(this.data);
}

/// A push click event whose payload is not a map at all.
class FakePayloadlessEvent {
  /// The payload, of a type no deeplink can be read from.
  final String data = 'not a map';
}

/// Stands in for `magic_notifications`' `NotificationManager`.
class FakeNotificationManager {
  final StreamController<FakePushNotificationEvent> _clicks =
      StreamController<FakePushNotificationEvent>.broadcast();

  /// Push notifications the user tapped.
  Stream<FakePushNotificationEvent> get onPushClicked => _clicks.stream;

  /// Publishes a tapped push carrying [data].
  void publishClick(Map<String, dynamic> data) =>
      _clicks.add(FakePushNotificationEvent(data));

  /// Closes the click stream.
  Future<void> dispose() => _clicks.close();
}

/// A notifications manager that publishes events carrying no readable payload.
class FakePayloadlessNotificationManager {
  final StreamController<FakePayloadlessEvent> _clicks =
      StreamController<FakePayloadlessEvent>.broadcast();

  /// Push notifications the user tapped.
  Stream<FakePayloadlessEvent> get onPushClicked => _clicks.stream;

  /// Publishes a tapped push whose payload is unreadable.
  void publishClick() => _clicks.add(FakePayloadlessEvent());

  /// Closes the click stream.
  Future<void> dispose() => _clicks.close();
}

/// A notifications manager with no click stream at all.
class FakeShapelessNotificationManager {
  /// The one thing this build offers, and not the click stream.
  String get name => 'shapeless';
}

/// A deeplink manager that records what it was asked to handle.
class RecordingDeeplinkManager implements DeeplinkManager {
  /// The URIs this manager was handed, in order.
  final List<Uri> handled = [];

  @override
  Future<bool> handleUri(Uri uri) async {
    handled.add(uri);

    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('OneSignalDeeplinkHandler', () {
    late OneSignalDeeplinkHandler handler;
    late RecordingDeeplinkManager deeplinks;

    setUp(() {
      MagicApp.reset();
      handler = OneSignalDeeplinkHandler();
      deeplinks = RecordingDeeplinkManager();
    });

    tearDown(() {
      handler.dispose();
    });

    test('extractUri supports multiple keys', () {
      expect(handler.extractUri({'url': 'https://a.com'}),
          Uri.parse('https://a.com'));
      expect(handler.extractUri({'deep_link': 'https://b.com'}),
          Uri.parse('https://b.com'));
      expect(handler.extractUri({'link': 'https://c.com'}),
          Uri.parse('https://c.com'));
      expect(handler.extractUri({'uri': 'https://d.com'}),
          Uri.parse('https://d.com'));
    });

    test('extractUri returns null if no url found', () {
      expect(handler.extractUri({'other': 'value'}), isNull);
    });

    test('extractData reads the payload off an event without naming its type',
        () {
      expect(
        handler
            .extractData(const FakePushNotificationEvent({'deep_link': 'x'})),
        equals({'deep_link': 'x'}),
      );
    });

    test('extractData reports an event carrying no payload', () {
      final log = Log.fake();

      expect(handler.extractData('a push nobody shaped'), isNull);
      expect(log.entries.where((entry) => entry.level == 'error'), isNotEmpty);
    });

    test('setup routes a click carrying deep_link to the deeplink manager',
        () async {
      final notifications = FakeNotificationManager();

      handler.setup(deeplinks, notifications);
      notifications.publishClick({
        'deep_link': 'https://uptizm.com/incidents/42',
        'title': 'Monitor down',
      });
      await Future<void>.delayed(Duration.zero);

      expect(deeplinks.handled, [Uri.parse('https://uptizm.com/incidents/42')]);

      await notifications.dispose();
    });

    test('setup ignores a click carrying no deeplink', () async {
      final notifications = FakeNotificationManager();

      handler.setup(deeplinks, notifications);
      notifications.publishClick({'title': 'Monitor down'});
      await Future<void>.delayed(Duration.zero);

      expect(deeplinks.handled, isEmpty);

      await notifications.dispose();
    });

    test('setup reports a manager that publishes no click stream', () {
      final log = Log.fake();

      handler.setup(deeplinks, FakeShapelessNotificationManager());

      expect(
        log.entries.where(
          (entry) =>
              entry.level == 'error' && entry.message.contains('onPushClicked'),
        ),
        isNotEmpty,
      );
    });

    test('setup reports a click whose payload cannot be read', () async {
      final log = Log.fake();
      final notifications = FakePayloadlessNotificationManager();

      handler.setup(deeplinks, notifications);
      notifications.publishClick();
      await Future<void>.delayed(Duration.zero);

      expect(deeplinks.handled, isEmpty);
      expect(log.entries.where((entry) => entry.level == 'error'), isNotEmpty);

      await notifications.dispose();
    });

    test('setup stays quiet when the host bound no log', () {
      expect(Magic.bound('log'), isFalse);
      expect(
        () => handler.setup(deeplinks, FakeShapelessNotificationManager()),
        returnsNormally,
      );
    });
  });
}
