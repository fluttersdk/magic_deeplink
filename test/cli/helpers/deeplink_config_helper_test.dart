import 'package:test/test.dart';
import 'package:magic_deeplink/src/cli/helpers/deeplink_config_helper.dart';

void main() {
  group('DeeplinkConfigHelper', () {
    late String template;

    setUp(() {
      template = DeeplinkConfigHelper.getDeeplinkConfigTemplate();
    });

    test('template contains the primary getter definition', () {
      expect(
        template,
        contains('Map<String, dynamic> get deeplinkConfig => {'),
      );
    });

    test('template contains the outer deeplink key', () {
      expect(
        template,
        contains("'deeplink': {"),
      );
    });

    test('template defines core configuration properties', () {
      expect(
        template,
        contains("'enabled': true,"),
      );
      expect(
        template,
        contains("'driver': 'app_links',"),
      );
      expect(
        template,
        contains("'domain': 'example.com',"),
      );
      expect(
        template,
        contains("'scheme': 'https',"),
      );
    });

    test('template contains ios specific configuration', () {
      expect(
        template,
        contains("'ios': {"),
      );
      expect(
        template,
        contains("'team_id': 'YOUR_TEAM_ID',"),
      );
      expect(
        template,
        contains("'bundle_id': 'com.example.app',"),
      );
    });

    test('template contains android specific configuration', () {
      expect(
        template,
        contains("'android': {"),
      );
      expect(
        template,
        contains("'package_name': 'com.example.app',"),
      );
      expect(
        template,
        contains("'sha256_fingerprints': ["),
      );
      expect(
        template,
        contains("'YOUR_SHA256_FINGERPRINT',"),
      );
    });

    test('template contains paths configuration', () {
      expect(
        template,
        contains("'paths': ["),
      );
      expect(
        template,
        contains("'/*',"),
      );
    });
  });
}
