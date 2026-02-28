import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_deeplink/src/handlers/onesignal_deeplink_handler.dart';
import 'package:magic_deeplink/src/deeplink_manager.dart';

// Mock DeeplinkManager
class MockDeeplinkManager implements DeeplinkManager {
  Uri? lastHandledUri;

  @override
  Future<bool> handleUri(Uri uri) async {
    lastHandledUri = uri;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('OneSignalDeeplinkHandler', () {
    late OneSignalDeeplinkHandler handler;

    setUp(() {
      handler = OneSignalDeeplinkHandler();
    });

    test('extractUri supports multiple keys', () {
      expect(
        handler.extractUri({'url': 'https://a.com'}),
        Uri.parse('https://a.com')
      );
      expect(
        handler.extractUri({'deep_link': 'https://b.com'}),
        Uri.parse('https://b.com')
      );
      expect(
        handler.extractUri({'link': 'https://c.com'}),
        Uri.parse('https://c.com')
      );
      expect(
        handler.extractUri({'uri': 'https://d.com'}),
        Uri.parse('https://d.com')
      );
    });

    test('extractUri returns null if no url found', () {
      expect(handler.extractUri({'other': 'value'}), isNull);
    });

    test('setup subscribes to stream and handles uri', () async {
      final mockManager = MockDeeplinkManager();
      final controller = StreamController<Map<String, dynamic>>();

      handler.setup(mockManager, controller.stream);

      // Emit event with URL
      controller.add({'url': 'https://uptizm.com/test'});

      // Wait for stream to process
      await Future.delayed(Duration.zero);

      expect(mockManager.lastHandledUri, equals(Uri.parse('https://uptizm.com/test')));

      await controller.close();
    });

    test('setup ignores events without uri', () async {
      final mockManager = MockDeeplinkManager();
      final controller = StreamController<Map<String, dynamic>>();

      handler.setup(mockManager, controller.stream);

      // Emit event without URL
      controller.add({'other': 'data'});

      // Wait for stream to process
      await Future.delayed(Duration.zero);

      expect(mockManager.lastHandledUri, isNull);

      await controller.close();
    });
  });
}
