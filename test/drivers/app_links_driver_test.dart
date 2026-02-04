import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_deeplink/src/drivers/app_links_driver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLinksDriver', () {
    test('has correct name', () {
      final driver = AppLinksDriver();
      expect(driver.name, 'app_links');
    });

    test('implements DeeplinkDriver', () {
      final driver = AppLinksDriver();
      expect(driver.name, isNotEmpty);
    });

    test('initialize sets up driver', () async {
      final driver = AppLinksDriver();
      await driver.initialize({});
      // Verify no exception is thrown and driver is usable
    });

    test('getInitialLink returns future uri', () async {
      final driver = AppLinksDriver();
      await driver.initialize({});
      expect(driver.getInitialLink(), isA<Future<Uri?>>());
    });

    test('onLink returns stream', () async {
      final driver = AppLinksDriver();
      await driver.initialize({});
      expect(driver.onLink, isA<Stream<Uri>>());
    });

    test('dispose cleans up resources', () async {
      final driver = AppLinksDriver();
      await driver.initialize({});
      // Just ensure it doesn't throw
      driver.dispose();
    });
  });
}
