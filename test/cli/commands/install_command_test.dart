import 'dart:io';

import 'package:magic_deeplink/src/cli/commands/install_command.dart';
import 'package:test/test.dart';

// A test subclass that overrides getProjectRoot() and stub paths
class TestInstallCommand extends InstallCommand {
  final String root;
  final List<String>? stubPaths;

  TestInstallCommand(this.root, [this.stubPaths]);

  @override
  String getProjectRoot() => root;

  @override
  List<String> getStubSearchPaths() => stubPaths ?? super.getStubSearchPaths();
}

void main() {
  group('InstallCommand', () {
    late Directory tempDir;
    late TestInstallCommand command;

    // Point directly to real stubs relative to the test location
    final stubsPath = Directory('${Directory.current.path}/assets/stubs').path;

    void setupAppFile() {
      final appFile = File('${tempDir.path}/lib/config/app.dart');
      appFile.createSync(recursive: true);
      appFile.writeAsStringSync('''
import 'package:magic/magic.dart';

import '../app/providers/app_service_provider.dart';
import '../app/providers/route_service_provider.dart';

Map<String, dynamic> get appConfig => {
  'app': {
    'name': env('APP_NAME', 'Test App'),
    'providers': [
      (app) => RouteServiceProvider(app),
      (app) => AppServiceProvider(app),
    ],
  },
};
''');
    }

    void setupMainFile() {
      final mainFile = File('${tempDir.path}/lib/main.dart');
      mainFile.createSync(recursive: true);
      mainFile.writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';

import 'config/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    configFactories: [
      () => appConfig,
    ],
  );

  runApp(const MyApp());
}
''');
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('install_command_test_');
      command = TestInstallCommand(tempDir.path, [stubsPath]);
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
      expect(() => command.runWith(['--force']),
          throwsException); // throws since app.dart doesn't exist yet
    });

    test('--force flag abbr is f', () {
      final cmd2 = TestInstallCommand(tempDir.path, [stubsPath]);
      expect(() => cmd2.runWith(['-f']), throwsException);
    });

    test('errors when Magic not installed (no lib/config/app.dart)', () async {
      expect(
        () => command.runWith([]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Magic Framework not detected'),
          ),
        ),
      );
    });

    test('handle creates lib/config/deeplink.dart', () async {
      setupAppFile();
      setupMainFile();

      await command.runWith([]);

      final configFile = File('${tempDir.path}/lib/config/deeplink.dart');
      expect(configFile.existsSync(), isTrue);

      final content = configFile.readAsStringSync();
      expect(content, contains('deeplinkConfig'));
      expect(content, contains("'deeplink':"));
    });

    test('handle skips write when file exists and no --force', () async {
      setupAppFile();
      setupMainFile();

      final configFile = File('${tempDir.path}/lib/config/deeplink.dart');
      configFile.createSync(recursive: true);
      configFile.writeAsStringSync('// original content');

      await command.runWith([]);

      expect(configFile.readAsStringSync(), '// original content');
    });

    test('handle overwrites when --force is set', () async {
      setupAppFile();
      setupMainFile();

      final configFile = File('${tempDir.path}/lib/config/deeplink.dart');
      configFile.createSync(recursive: true);
      configFile.writeAsStringSync('// original content');

      await command.runWith(['--force']);

      final content = configFile.readAsStringSync();
      expect(content, contains('deeplinkConfig'));
      expect(content, isNot(contains('// original content')));
    });

    test('handle creates parent directories', () async {
      setupAppFile();
      setupMainFile();

      expect(
        Directory('${tempDir.path}/lib/config/deeplink.dart').existsSync(),
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

    test('injects import into app.dart', () async {
      setupAppFile();
      setupMainFile();

      await command.runWith([]);

      final appContent =
          File('${tempDir.path}/lib/config/app.dart').readAsStringSync();
      expect(appContent,
          contains("import 'package:magic_deeplink/magic_deeplink.dart';"));
    });

    test('injects provider into app.dart providers list', () async {
      setupAppFile();
      setupMainFile();

      await command.runWith([]);

      final appContent =
          File('${tempDir.path}/lib/config/app.dart').readAsStringSync();
      expect(appContent, contains('(app) => DeeplinkServiceProvider(app),'));
    });

    test('injects import into main.dart', () async {
      setupAppFile();
      setupMainFile();

      await command.runWith([]);

      final mainContent =
          File('${tempDir.path}/lib/main.dart').readAsStringSync();
      expect(mainContent, contains("import 'config/deeplink.dart';"));
    });

    test('injects configFactory into main.dart', () async {
      setupAppFile();
      setupMainFile();

      await command.runWith([]);

      final mainContent =
          File('${tempDir.path}/lib/main.dart').readAsStringSync();
      expect(mainContent, contains('() => deeplinkConfig,'));
    });

    test('idempotent — running twice does not duplicate injections', () async {
      setupAppFile();
      setupMainFile();

      await command.runWith([]);
      await command.runWith([]);

      final appContent =
          File('${tempDir.path}/lib/config/app.dart').readAsStringSync();
      final mainContent =
          File('${tempDir.path}/lib/main.dart').readAsStringSync();

      final providerMatches =
          RegExp(r'DeeplinkServiceProvider').allMatches(appContent);
      expect(providerMatches.length, 1,
          reason: 'Provider should only be injected once');

      final factoryMatches =
          RegExp(r'\(\) => deeplinkConfig').allMatches(mainContent);
      expect(factoryMatches.length, 1,
          reason: 'Config factory should only be injected once');
    });
  });
}
