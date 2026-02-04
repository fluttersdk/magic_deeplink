import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_deeplink/src/cli/helpers/deeplink_config_helper.dart';

void main() {
  group('DeeplinkConfigHelper', () {
    test('getDeeplinkConfigTemplate returns valid dart code', () {
      final config = DeeplinkConfigHelper.getDeeplinkConfigTemplate();

      expect(config, contains("Map<String, dynamic> get deeplinkConfig => {"));
      expect(config, contains("'deeplink': {"));
      expect(config, contains("'driver': 'app_links'"));
      expect(config, contains("'paths': ["));
      expect(config, contains("'ios': {"));
      expect(config, contains("'android': {"));
    });
  });
}
