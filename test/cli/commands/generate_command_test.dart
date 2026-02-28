import 'dart:convert';
import 'dart:io';

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
      tempDir.deleteSync(recursive: true);
    });

    // -----------------------------------------------------------------------
    // Identity
    // -----------------------------------------------------------------------

    test('name is generate', () {
      expect(command.name, 'generate');
    });

    test('description mentions deep link or configuration files', () {
      expect(
        command.description.toLowerCase(),
        anyOf(
          contains('deep link'),
          contains('configuration files'),
          contains('generate'),
        ),
      );
    });

    // -----------------------------------------------------------------------
    // configure() — option registration via runWith
    // -----------------------------------------------------------------------

    test('configure accepts --output option', () {
      expect(() => command.runWith(['--output', 'out']), returnsNormally);
    });

    test('configure accepts -o short option', () {
      final cmd2 = _TestGenerateCommand(tempDir.path);
      expect(() => cmd2.runWith(['-o', 'out']), returnsNormally);
    });

    test('configure accepts --root option', () {
      final cmd2 = _TestGenerateCommand(tempDir.path);
      expect(() => cmd2.runWith(['--root', '.']), returnsNormally);
    });

    test('configure accepts --team-id option', () {
      final cmd2 = _TestGenerateCommand(tempDir.path);
      expect(
        () => cmd2.runWith(['--team-id', 'TEAMID']),
        returnsNormally,
      );
    });

    test('configure accepts --bundle-id option', () {
      final cmd2 = _TestGenerateCommand(tempDir.path);
      expect(
        () => cmd2.runWith(['--bundle-id', 'com.app']),
        returnsNormally,
      );
    });

    test('configure accepts --package-name option', () {
      final cmd2 = _TestGenerateCommand(tempDir.path);
      expect(
        () => cmd2.runWith(['--package-name', 'com.app']),
        returnsNormally,
      );
    });

    test('configure accepts --sha256-fingerprints multi-option', () {
      final cmd2 = _TestGenerateCommand(tempDir.path);
      expect(
        () => cmd2.runWith([
          '--sha256-fingerprints',
          'AA:BB',
          '--sha256-fingerprints',
          'CC:DD'
        ]),
        returnsNormally,
      );
    });

    test('configure accepts --paths multi-option', () {
      final cmd2 = _TestGenerateCommand(tempDir.path);
      expect(
        () => cmd2.runWith(['--paths', '/api/*', '--paths', '/app/*']),
        returnsNormally,
      );
    });

    // -----------------------------------------------------------------------
    // buildAppleAppSiteAssociation()
    // -----------------------------------------------------------------------

    test('buildAppleAppSiteAssociation returns correct appID', () {
      final result = command.buildAppleAppSiteAssociation(
        'TEAM1',
        'com.example.app',
        ['/*'],
      );

      final details = (result['applinks'] as Map)['details'] as List;
      expect(details.first['appID'], 'TEAM1.com.example.app');
    });

    test('buildAppleAppSiteAssociation returns correct paths', () {
      final result = command.buildAppleAppSiteAssociation(
        'TEAM1',
        'com.example.app',
        ['/products/*', '/orders/*'],
      );

      final details = (result['applinks'] as Map)['details'] as List;
      expect(details.first['paths'], ['/products/*', '/orders/*']);
    });

    test('buildAppleAppSiteAssociation result is JSON-serialisable', () {
      final result = command.buildAppleAppSiteAssociation(
        'TEAM1',
        'com.example.app',
        ['/*'],
      );

      expect(() => jsonEncode(result), returnsNormally);
    });

    // -----------------------------------------------------------------------
    // buildAssetLinks()
    // -----------------------------------------------------------------------

    test('buildAssetLinks returns list with correct package_name', () {
      final result = command.buildAssetLinks('com.example.app', ['FP1']);

      final first = result.first as Map;
      final target = first['target'] as Map;
      expect(target['package_name'], 'com.example.app');
    });

    test('buildAssetLinks includes sha256_cert_fingerprints', () {
      final result = command.buildAssetLinks('com.example.app', ['AA:BB']);

      final first = result.first as Map;
      final target = first['target'] as Map;
      expect(target['sha256_cert_fingerprints'], contains('AA:BB'));
    });

    test('buildAssetLinks with two fingerprints returns two entries', () {
      final result = command.buildAssetLinks('com.example.app', ['FP1', 'FP2']);

      expect(result, hasLength(2));
    });

    test('buildAssetLinks result is JSON-serialisable', () {
      final result = command.buildAssetLinks('com.example.app', ['FP1']);

      expect(() => jsonEncode(result), returnsNormally);
    });

    // -----------------------------------------------------------------------
    // handle() — integration with temp dir
    // -----------------------------------------------------------------------

    test('handle writes apple-app-site-association to output directory',
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
    });

    test('handle writes assetlinks.json to output directory', () async {
      final cmd2 = _TestGenerateCommand(tempDir.path);
      await cmd2.runWith([
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

      final assetLinksFile = File('${tempDir.path}/public/assetlinks.json');
      expect(assetLinksFile.existsSync(), isTrue);
    });
  });
}
