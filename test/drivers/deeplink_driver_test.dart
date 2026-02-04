import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_deeplink/src/drivers/deeplink_driver.dart';

class TestDeeplinkDriver extends DeeplinkDriver {
  @override
  String get name => 'test';

  @override
  bool get isSupported => true;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}

  @override
  Future<Uri?> getInitialLink() async => Uri.parse('https://example.com');

  @override
  Stream<Uri> get onLink => Stream.value(Uri.parse('https://example.com/stream'));

  @override
  void dispose() {}
}

void main() {
  group('DeeplinkDriver', () {
    test('contract defines required methods', () async {
      final driver = TestDeeplinkDriver();
      expect(driver.name, 'test');
      expect(driver.isSupported, isTrue);
      await driver.initialize({});
      expect(await driver.getInitialLink(), isNotNull);
      expect(driver.onLink, isA<Stream<Uri>>());
      driver.dispose();
    });
  });
}
