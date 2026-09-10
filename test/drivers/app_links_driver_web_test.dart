@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_deeplink/src/drivers/app_links_driver.dart';

void main() {
  group('AppLinksDriver (web)', () {
    test('is an explicit no-op: unsupported, no initial link, empty stream',
        () async {
      final driver = AppLinksDriver();

      expect(driver.isSupported, isFalse);
      expect(await driver.getInitialLink(), isNull);
      expect(await driver.onLink.toList(), isEmpty);
    });
  });
}
