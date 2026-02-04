import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_deeplink/src/exceptions/deeplink_exception.dart';

void main() {
  group('DeeplinkException', () {
    test('has message and code', () {
      final exception = DeeplinkException('Test message', code: 'TEST_CODE');
      expect(exception.message, equals('Test message'));
      expect(exception.code, equals('TEST_CODE'));
    });

    test('toString returns message', () {
      final exception = DeeplinkException('Test message');
      expect(exception.toString(), contains('Test message'));
    });
  });
}
