import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_deeplink/src/cli/commands/generate_command.dart';

void main() {
  group('GenerateCommand', () {
    test('has correct name and description', () {
      final command = GenerateCommand();
      expect(command.name, 'generate');
      expect(command.description, contains('Generate deep link configuration files'));
    });

    test('accepts output directory option', () {
      final command = GenerateCommand();
      final parser = command.argParser;
      expect(parser.options.containsKey('output'), isTrue);
    });

    test('accepts project root option', () {
      final command = GenerateCommand();
      final parser = command.argParser;
      expect(parser.options.containsKey('root'), isTrue);
    });

    test('generateAppleAppSiteAssociation creates valid JSON', () {
      final command = GenerateCommand();
      final config = {
        'deeplink': {
          'ios': {
            'team_id': 'TEAMID',
            'bundle_id': 'com.example.app',
          },
          'paths': ['/path/*']
        }
      };

      final json = command.generateAppleAppSiteAssociation(config);
      expect(json, contains('"appID": "TEAMID.com.example.app"'));
      expect(json, contains('"/path/*"'));
      expect(json, contains('"applinks":'));
    });

    test('generateAssetLinks creates valid JSON', () {
      final command = GenerateCommand();
      final config = {
        'deeplink': {
          'android': {
            'package_name': 'com.example.app',
            'sha256_fingerprints': ['FINGERPRINT_HASH']
          }
        }
      };

      final json = command.generateAssetLinks(config);
      expect(json, contains('"package_name": "com.example.app"'));
      expect(json, contains('"sha256_cert_fingerprints": ['));
      expect(json, contains('"FINGERPRINT_HASH"'));
      expect(json, contains('"relation": ['));
    });
  });
}
