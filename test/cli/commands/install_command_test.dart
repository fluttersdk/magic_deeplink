import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic_deeplink/src/cli/commands/install_command.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test subclass that pins the manifest path + buildContext to a real tempDir.
// ---------------------------------------------------------------------------

/// Pins [resolveManifestPath] to the package-local install.yaml and
/// [buildContext] to a real-FS context rooted at [projectRoot].
///
/// This avoids [Isolate.resolvePackageUri] lookups in tests and ensures the
/// ConfigEditor helpers (which bypass VirtualFs) write to the temp directory.
class _TestableInstallCommand extends InstallCommand {
  _TestableInstallCommand({
    required this.manifestPath,
    required this.projectRoot,
  });

  final String manifestPath;
  final String projectRoot;

  @override
  Future<String?> resolveManifestPath() async => manifestPath;

  @override
  InstallContext buildContext(ArtisanContext ctx) =>
      InstallContext.real(ctx, projectRoot: projectRoot);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns the absolute path to the package-root install.yaml.
String get _packageManifest => '${Directory.current.path}/install.yaml';

/// Returns the absolute path to the magic_deeplink package root.
String get _pluginRoot => Directory.current.path;

/// Builds an [ArtisanContext] for the given [flags] against the command's
/// parsed signature.
ArtisanContext _ctx(
  InstallCommand cmd, {
  Map<String, dynamic> flags = const <String, dynamic>{},
}) {
  final defaults = <String, dynamic>{
    'force': false,
    'dry-run': false,
    'non-interactive': true,
    'no-bootstrap': false,
  };
  return ArtisanContext.bare(
    MapInput({...defaults, ...flags}, signature: cmd.parsedSignature),
    BufferedOutput(),
  );
}

/// Seeds a minimal but valid Magic project scaffold into [root]:
/// - `.dart_tool/package_config.json` pointing at the real magic_deeplink stubs
/// - `lib/config/app.dart` with a providers list
/// - `lib/main.dart` with a configFactories list
void _seedProject(String root) {
  // Seed package_config.json so ManifestInstaller._resolvePluginStubsDir can
  // locate magic_deeplink's assets/stubs/ directory. The rootUri is built with
  // Uri.directory so it is a well-formed file:// URI on POSIX regardless of the
  // plugin root path.
  File('$root/.dart_tool/package_config.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '{"configVersion":2,"packages":['
      '{"name":"magic_deeplink","rootUri":"${Uri.directory(_pluginRoot)}","packageUri":"lib/"}'
      ']}',
    );

  File('$root/lib/config/app.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:magic/magic.dart';

Map<String, dynamic> get appConfig => {
  'app': {
    'providers': [
      (app) => AppServiceProvider(app),
    ],
  },
};
''');

  File('$root/lib/main.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';

import 'config/app.dart';

void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
    ],
  );
}
''');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;
  late _TestableInstallCommand command;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('deeplink_install_test_');
    command = _TestableInstallCommand(
      manifestPath: _packageManifest,
      projectRoot: tempDir.path,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // -------------------------------------------------------------------------
  // Group 1: command metadata
  // -------------------------------------------------------------------------

  group('InstallCommand, metadata', () {
    test('extends ArtisanInstallCommand', () {
      expect(command, isA<ArtisanInstallCommand>());
    });

    test('signature starts with deeplink:install', () {
      expect(command.signature, startsWith('deeplink:install'));
    });

    test('includes the 4 base flags from ArtisanInstallCommand', () {
      final optionNames =
          command.parsedSignature!.options.map((o) => o.name).toSet();
      expect(
        optionNames,
        containsAll(
            <String>['force', 'dry-run', 'non-interactive', 'no-bootstrap']),
      );
    });

    test('boot is CommandBoot.none', () {
      expect(command.boot, CommandBoot.none);
    });
  });

  // -------------------------------------------------------------------------
  // Group 2: manifest-driven install
  // -------------------------------------------------------------------------

  group('InstallCommand, manifest-driven install', () {
    test('publishes lib/config/deeplink.dart from stub', () async {
      _seedProject(tempDir.path);

      final ctx = _ctx(command);
      final exitCode = await command.handle(ctx);

      expect(exitCode, 0);
      final configFile = File('${tempDir.path}/lib/config/deeplink.dart');
      expect(configFile.existsSync(), isTrue);
      final content = configFile.readAsStringSync();
      expect(content, contains('deeplinkConfig'));
      expect(content, contains("'deeplink':"));
    });

    test('injects DeeplinkServiceProvider into app.dart', () async {
      _seedProject(tempDir.path);

      final ctx = _ctx(command);
      await command.handle(ctx);

      final appContent =
          File('${tempDir.path}/lib/config/app.dart').readAsStringSync();
      expect(appContent, contains('DeeplinkServiceProvider'));
    });

    test('injects deeplinkConfig factory into main.dart', () async {
      _seedProject(tempDir.path);

      final ctx = _ctx(command);
      await command.handle(ctx);

      final mainContent =
          File('${tempDir.path}/lib/main.dart').readAsStringSync();
      expect(mainContent, contains('deeplinkConfig'));
    });

    test('returns exit code 0 on success', () async {
      _seedProject(tempDir.path);

      final ctx = _ctx(command);
      final exitCode = await command.handle(ctx);

      expect(exitCode, 0);
    });

    test('skips config write when file exists and --force not set', () async {
      _seedProject(tempDir.path);
      final configFile = File('${tempDir.path}/lib/config/deeplink.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('// original content');

      final ctx = _ctx(command);
      await command.handle(ctx);

      expect(configFile.readAsStringSync(), contains('// original content'));
    });

    test('overwrites config when --force is set', () async {
      _seedProject(tempDir.path);
      File('${tempDir.path}/lib/config/deeplink.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('// original content');

      final ctx = _ctx(command, flags: {'force': true});
      await command.handle(ctx);

      final content =
          File('${tempDir.path}/lib/config/deeplink.dart').readAsStringSync();
      expect(content, contains('deeplinkConfig'));
      expect(content, isNot(contains('// original content')));
    });
  });

  // -------------------------------------------------------------------------
  // Group 3: dry-run
  // -------------------------------------------------------------------------

  group('InstallCommand, dry-run', () {
    test('dry-run does not write config file', () async {
      _seedProject(tempDir.path);

      final ctx = _ctx(command, flags: {'dry-run': true});
      final exitCode = await command.handle(ctx);

      expect(exitCode, 0);
      expect(
        File('${tempDir.path}/lib/config/deeplink.dart').existsSync(),
        isFalse,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 4: idempotency
  // -------------------------------------------------------------------------

  group('InstallCommand, idempotency', () {
    test('running twice does not duplicate provider injection', () async {
      _seedProject(tempDir.path);

      await command.handle(_ctx(command));
      // Construct a fresh command instance for the second run (one-shot guard).
      final command2 = _TestableInstallCommand(
        manifestPath: _packageManifest,
        projectRoot: tempDir.path,
      );
      await command2.handle(_ctx(command2));

      final appContent =
          File('${tempDir.path}/lib/config/app.dart').readAsStringSync();
      final matches = RegExp('DeeplinkServiceProvider').allMatches(appContent);
      expect(matches.length, 1,
          reason: 'Provider should only be injected once');
    });

    test('running twice does not duplicate config factory injection', () async {
      _seedProject(tempDir.path);

      await command.handle(_ctx(command));
      final command2 = _TestableInstallCommand(
        manifestPath: _packageManifest,
        projectRoot: tempDir.path,
      );
      await command2.handle(_ctx(command2));

      final mainContent =
          File('${tempDir.path}/lib/main.dart').readAsStringSync();
      // deeplinkConfig appears once in configFactories injection; the
      // deeplink.dart file itself is written to lib/config/ not main.dart.
      final matches = RegExp(r'deeplinkConfig').allMatches(mainContent);
      expect(matches.length, 1,
          reason: 'Config factory should only be injected once');
    });
  });
}
