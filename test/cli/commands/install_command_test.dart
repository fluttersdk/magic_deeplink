import 'dart:io';

import 'package:test/test.dart';

import 'package:magic_deeplink/src/cli/commands/install_command.dart';

// A test subclass that overrides getProjectRoot() to use a temp dir
class TestInstallCommand extends InstallCommand {
  final String root;

  TestInstallCommand(this.root);

  @override
  String getProjectRoot() => root;
}

void main() {
  group('InstallCommand', () {
    late Directory tempDir;
    late TestInstallCommand command;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('install_command_test_');
      command = TestInstallCommand(tempDir.path);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('name is install', () {
      expect(command.name, 'install');
    });

    test('description contains deep link or configuration', () {
      expect(
        command.description.toLowerCase(),
        anyOf(
          contains('deep link'),
          contains('configuration'),
        ),
      );
    });

    test('configure adds --force flag with abbr f', () {
      expect(() => command.runWith(['--force']), returnsNormally);
    });

    test('--force flag abbr is f', () {
      final cmd2 = TestInstallCommand(tempDir.path);
      expect(() => cmd2.runWith(['-f']), returnsNormally);
    });

    test('handle creates lib/config/deeplink.dart', () async {
      await command.runWith([]);

      final configFile = File('${tempDir.path}/lib/config/deeplink.dart');
      expect(configFile.existsSync(), isTrue);

      final content = configFile.readAsStringSync();
      expect(content, contains('deeplinkConfig'));
      expect(content, contains("'deeplink':"));
    });

    test('handle skips write when file exists and no --force', () async {
      final configFile = File('${tempDir.path}/lib/config/deeplink.dart');
      configFile.createSync(recursive: true);
      configFile.writeAsStringSync('// original content');

      await command.runWith([]);

      expect(configFile.readAsStringSync(), '// original content');
    });

    test('handle overwrites when --force is set', () async {
      final configFile = File('${tempDir.path}/lib/config/deeplink.dart');
      configFile.createSync(recursive: true);
      configFile.writeAsStringSync('// original content');

      await command.runWith(['--force']);

      final content = configFile.readAsStringSync();
      expect(content, contains('deeplinkConfig'));
      expect(content, isNot(contains('// original content')));
    });

    test('handle creates parent directories', () async {
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
