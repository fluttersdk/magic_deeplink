import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

/// CLI command to install the deep link configuration file into the project.
///
/// Writes `lib/config/deeplink.dart` to the current working directory.
/// Skips the write if the file already exists unless `--force` is passed.
/// Injects providers and configFactories into the host Magic app.
///
/// ## Usage
///
/// ```bash
/// dart run artisan deeplink:install
/// dart run artisan deeplink:install --force
/// ```
class InstallCommand extends ArtisanCommand {
  @override
  String get signature =>
      'deeplink:install {--force : Overwrite existing configuration file.}';

  @override
  String get description =>
      'Install deep link configuration and inject into Magic app.';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// Return the Flutter project root directory.
  ///
  /// Overridable in tests to point at a temp directory without requiring
  /// a real pubspec.yaml to be present on disk.
  String getProjectRoot() {
    return FileHelper.findProjectRoot();
  }

  /// Returns the paths to search for stubs.
  ///
  /// Overridable in tests.
  List<String> getStubSearchPaths() {
    return [_resolvePluginStubsDir(), '${Directory.current.path}/assets/stubs'];
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Read CLI flags before doing any file work.
    final force = ctx.input.option('force') as bool? ?? false;
    final root = getProjectRoot();
    final appPath = '$root/lib/config/app.dart';
    final mainPath = '$root/lib/main.dart';
    final configPath = '$root/lib/config/deeplink.dart';

    ctx.output.info('Installing deep link configuration...');

    // 2. Validate Magic is installed.
    if (!FileHelper.fileExists(appPath)) {
      ctx.output.error(
        'Magic Framework not detected. Run `magic install` first.',
      );
      return 1;
    }

    // 3. Write config file.
    if (FileHelper.fileExists(configPath) && !force) {
      ctx.output.warning(
        'Configuration file already exists. Use --force to overwrite.',
      );
    } else {
      final configContent = StubLoader.load(
        'install/deeplink_config',
        searchPaths: getStubSearchPaths(),
      );
      FileHelper.writeFile(configPath, configContent);
      ctx.output.success('Created lib/config/deeplink.dart');
    }

    // 4. Inject into app.dart.
    _injectIntoApp(ctx, appPath);

    // 5. Inject into main.dart.
    _injectIntoMain(ctx, mainPath);

    ctx.output.success('Deeplink configuration installed successfully!');
    return 0;
  }

  /// Injects provider and imports into lib/config/app.dart.
  void _injectIntoApp(ArtisanContext ctx, String appPath) {
    ConfigEditor.addImportToFile(
      filePath: appPath,
      importStatement: "import 'package:magic_deeplink/magic_deeplink.dart';",
    );

    final content = FileHelper.readFile(appPath);
    if (!content.contains('DeeplinkServiceProvider')) {
      ConfigEditor.insertCodeBeforePattern(
        filePath: appPath,
        pattern: RegExp(r'\s+\]\,\s*\},?'),
        code: '      (app) => DeeplinkServiceProvider(app),\n',
      );
      ctx.output.success(
        'Injected DeeplinkServiceProvider into lib/config/app.dart',
      );
    }
  }

  /// Injects configFactory and imports into lib/main.dart.
  void _injectIntoMain(ArtisanContext ctx, String mainPath) {
    if (!FileHelper.fileExists(mainPath)) return;

    ConfigEditor.addImportToFile(
      filePath: mainPath,
      importStatement: "import 'config/deeplink.dart';",
    );

    final content = FileHelper.readFile(mainPath);
    if (!content.contains('deeplinkConfig')) {
      ConfigEditor.insertCodeBeforePattern(
        filePath: mainPath,
        pattern: RegExp(r'\s+\]\,\s*\);'),
        code: '      () => deeplinkConfig,\n',
      );
      ctx.output.success('Injected deeplinkConfig into lib/main.dart');
    }
  }

  /// Tries to resolve the package assets directory dynamically using package_config.json.
  String _resolvePluginStubsDir() {
    final packageConfigPath =
        '${Directory.current.path}/.dart_tool/package_config.json';
    if (File(packageConfigPath).existsSync()) {
      final content = File(packageConfigPath).readAsStringSync();
      try {
        final map = jsonDecode(content) as Map<String, dynamic>;
        final packages = map['packages'] as List<dynamic>? ?? [];
        for (final package in packages) {
          if (package['name'] == 'magic_deeplink') {
            final rootUri = package['rootUri'] as String;
            String parsedPath;
            if (rootUri.startsWith('file://')) {
              parsedPath = Uri.parse(rootUri).toFilePath();
            } else if (rootUri.startsWith('../')) {
              parsedPath = Uri.parse(rootUri).toFilePath();
              parsedPath = File(
                packageConfigPath,
              ).parent.parent.uri.resolve(rootUri).toFilePath();
            } else {
              parsedPath = rootUri;
            }
            return '$parsedPath/assets/stubs'.replaceAll('//', '/');
          }
        }
      } catch (_) {
        // Fallback below.
      }
    }
    return '${Directory.current.path}/assets/stubs';
  }
}
