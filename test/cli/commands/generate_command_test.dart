import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:test/test.dart';

import 'package:magic_deeplink/src/cli/commands/generate_command.dart';

/// Test subclass that overrides [getProjectRoot] to point at a temp directory.
class _TestGenerateCommand extends GenerateCommand {
  final String root;

  _TestGenerateCommand(this.root);

  @override
  String getProjectRoot() => root;
}

void main() {
  group('GenerateCommand', () {
    late Directory tempDir;
    late _TestGenerateCommand command;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('generate_command_test_');
      command = _TestGenerateCommand(tempDir.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    // -----------------------------------------------------------------------
    // Meta / Options
    // -----------------------------------------------------------------------

    test('name returns generate', () {
      expect(command.name, 'generate');
    });

    test('description contains deep link or configuration files', () {
      expect(
        command.description.toLowerCase(),
        anyOf(
          contains('deep link'),
          contains('configuration files'),
          contains('generate'),
        ),
      );
    });

    test('configure() adds --output option with abbr o and default public', () {
      final parser = ArgParser();
      command.configure(parser);
      final options = parser.options['output'];
      expect(options, isNotNull);
      expect(options?.abbr, 'o');
      expect(options?.defaultsTo, 'public');
    });

    test('configure() adds --root option with default .', () {
      final parser = ArgParser();
      command.configure(parser);
      final options = parser.options['root'];
      expect(options, isNotNull);
      expect(options?.defaultsTo, '.');
    });

    test('configure() adds --team-id option', () {
      final parser = ArgParser();
      command.configure(parser);
      expect(parser.options.containsKey('team-id'), isTrue);
    });

    test('configure() adds --bundle-id option', () {
      final parser = ArgParser();
      command.configure(parser);
      expect(parser.options.containsKey('bundle-id'), isTrue);
    });

    test('configure() adds --package-name option', () {
      final parser = ArgParser();
      command.configure(parser);
      expect(parser.options.containsKey('package-name'), isTrue);
    });

    test('configure() adds --sha256-fingerprints multi-option', () {
      final parser = ArgParser();
      command.configure(parser);
      expect(parser.options['sha256-fingerprints']?.isMultiple, isTrue);
    });

    test('configure() adds --paths multi-option', () {
      final parser = ArgParser();
      command.configure(parser);
      final options = parser.options['paths'];
      expect(options?.isMultiple, isTrue);
      expect(options?.defaultsTo, ['/*']);
    });

    // -----------------------------------------------------------------------
    // buildAppleAppSiteAssociation()
    // -----------------------------------------------------------------------

    test(
        'buildAppleAppSiteAssociation(T1, com.app, [/path/*]) returns map with applinks.details[0].appID == T1.com.app',
        () {
      final result = command.buildAppleAppSiteAssociation(
        'T1',
        'com.app',
        ['/path/*'],
      );

      final details = (result['applinks'] as Map)['details'] as List;
      expect(details.first['appID'], 'T1.com.app');
    });

    test(
        'buildAppleAppSiteAssociation(T1, com.app, [/path/*]) returns map with paths [/path/*]',
        () {
      final result = command.buildAppleAppSiteAssociation(
        'T1',
        'com.app',
        ['/path/*'],
      );

      final details = (result['applinks'] as Map)['details'] as List;
      expect(details.first['paths'], ['/path/*']);
    });

    // -----------------------------------------------------------------------
    // buildAssetLinks()
    // -----------------------------------------------------------------------

    test(
        'buildAssetLinks(com.app, [FINGERPRINT]) returns list with target.package_name == com.app',
        () {
      final result = command.buildAssetLinks('com.app', ['FINGERPRINT']);

      final first = result.first as Map;
      final target = first['target'] as Map;
      expect(target['package_name'], 'com.app');
    });

    test(
        'buildAssetLinks(com.app, [FP1, FP2]) returns list with 2 entries OR 1 entry with 2 fingerprints',
        () {
      final result = command.buildAssetLinks('com.app', ['FP1', 'FP2']);

      expect(result, hasLength(2));
      expect(((result[0] as Map)['target'] as Map)['sha256_cert_fingerprints'],
          ['FP1']);
      expect(((result[1] as Map)['target'] as Map)['sha256_cert_fingerprints'],
          ['FP2']);
    });

    // -----------------------------------------------------------------------
    // handle()
    // -----------------------------------------------------------------------

    test(
        'handle() with temp dir writes apple-app-site-association and assetlinks.json',
        () async {
      await command.runWith([
        '--output',
        'public',
        '--team-id',
        'TEAM1',
        '--bundle-id',
        'com.example.app',
        '--package-name',
        'com.example.app',
        '--sha256-fingerprints',
        'AA:BB:CC',
      ]);

      final aasaFile =
          File('${tempDir.path}/public/apple-app-site-association');
      expect(aasaFile.existsSync(), isTrue);

      final aasaJson = jsonDecode(aasaFile.readAsStringSync());
      expect(
        ((aasaJson['applinks'] as Map)['details'] as List).first['appID'],
        'TEAM1.com.example.app',
      );

      final assetLinksFile = File('${tempDir.path}/public/assetlinks.json');
      expect(assetLinksFile.existsSync(), isTrue);

      final assetLinksJson =
          jsonDecode(assetLinksFile.readAsStringSync()) as List;
      expect(
        (assetLinksJson.first['target'] as Map)['package_name'],
        'com.example.app',
      );
    });
  });
}
