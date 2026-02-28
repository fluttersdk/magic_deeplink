import 'dart:io';

import 'package:test/test.dart';

import 'package:magic_deeplink/src/cli/commands/install_command.dart';

/// Test subclass that overrides [getProjectRoot] to point at a temp directory.
class _TestInstallCommand extends InstallCommand {
  final String root;

  _TestInstallCommand(this.root);

  @override
  String getProjectRoot() => root;
}

void main() {
  group('InstallCommand', () {
    late Directory tempDir;
    late _TestInstallCommand command;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('install_command_test_');
      command = _TestInstallCommand(tempDir.path);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('name is install', () {
      expect(command.name, 'install');
    });

    test('description mentions deep link or configuration', () {
      expect(
        command.description.toLowerCase(),
        anyOf(
          contains('deep link'),
          contains('configuration'),
        ),
      );
    });

    test('configure accepts --force flag without error', () {
      // If --force is not registered, runWith throws FormatException.
      expect(() => command.runWith(['--force']), returnsNormally);
    });

    test('configure accepts -f abbr without error', () {
      final cmd2 = _TestInstallCommand(tempDir.path);
      expect(() => cmd2.runWith(['-f']), returnsNormally);
    });

    test('handle creates lib/config/deeplink.dart in project root', () async {
      await command.runWith([]);

      final configFile = File('${tempDir.path}/lib/config/deeplink.dart');
      expect(configFile.existsSync(), isTrue);
    });

    test('handle writes DeeplinkConfigHelper template content', () async {
      await command.runWith([]);

      final configFile = File('${tempDir.path}/lib/config/deeplink.dart');
      final content = configFile.readAsStringSync();
      expect(content, contains('deeplinkConfig'));
      expect(content, contains("'deeplink':"));
    });

    test('handle skips write when file exists and --force not set', () async {
      // Create the file first.
      final configFile = File('${tempDir.path}/lib/config/deeplink.dart');
      configFile.createSync(recursive: true);
      configFile.writeAsStringSync('// original content');

      await command.runWith([]);

      // Content should NOT be overwritten.
      expect(configFile.readAsStringSync(), '// original content');
    });

    test('handle overwrites when --force is set', () async {
      // Create the file first.
      final configFile = File('${tempDir.path}/lib/config/deeplink.dart');
      configFile.createSync(recursive: true);
      configFile.writeAsStringSync('// original content');

      await command.runWith(['--force']);

      // Content should be overwritten with template.
      final content = configFile.readAsStringSync();
      expect(content, contains('deeplinkConfig'));
      expect(content, isNot(contains('// original content')));
    });

    test('handle creates parent directories when they do not exist', () async {
      // Temp dir has no lib/config/ yet.
      expect(
        Directory('${tempDir.path}/lib/config').existsSync(),
        isFalse,
      );

      await command.runWith([]);

      expect(
        File('${tempDir.path}/lib/config/deeplink.dart').existsSync(),
        isTrue,
      );
    });

    test('getProjectRoot is overridable', () {
      expect(command.getProjectRoot(), tempDir.path);
    });
  });
}
