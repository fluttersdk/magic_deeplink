import 'dart:io';
import 'dart:isolate';

import 'package:fluttersdk_artisan/artisan.dart';

/// `deeplink:install`, installs magic_deeplink via the bundled install.yaml
/// manifest.
///
/// Driven entirely by the manifest: publishes lib/config/deeplink.dart from
/// the bundled stub, injects DeeplinkServiceProvider into lib/config/app.dart,
/// and injects the deeplinkConfig factory into lib/main.dart so the Magic IoC
/// container resolves the runtime Deeplink facade.
///
/// ## Usage
///
/// ```bash
/// dart run <app>:artisan deeplink:install
/// dart run <app>:artisan deeplink:install --force
/// dart run <app>:artisan deeplink:install --dry-run
/// ```
class InstallCommand extends ArtisanInstallCommand {
  @override
  String get signature => 'deeplink:install $baseFlags';

  @override
  String get description =>
      'Install magic_deeplink via the bundled manifest (config publish + provider + configFactory inject).';

  @override
  String pluginName(ArtisanContext ctx) => 'magic_deeplink';

  /// Resolves the absolute path to the bundled install.yaml.
  ///
  /// Uses [Isolate.resolvePackageUri] starting from
  /// `package:magic_deeplink/magic_deeplink.dart`. The barrel lives at
  /// `<plugin_root>/lib/magic_deeplink.dart`, so two parent lookups back out
  /// to the plugin root where install.yaml resides.
  ///
  /// Returns `null` when the manifest cannot be located so [handle] can
  /// surface a clean error.
  ///
  /// @return The absolute manifest path, or `null` when not found.
  Future<String?> resolveManifestPath() async {
    final resolved = await Isolate.resolvePackageUri(
      Uri.parse('package:magic_deeplink/magic_deeplink.dart'),
    );
    if (resolved == null || resolved.scheme != 'file') return null;

    // resolved -> <plugin_root>/lib/magic_deeplink.dart; two parent lookups
    // back out to the plugin root where install.yaml lives.
    final pluginRoot = File(resolved.toFilePath()).parent.parent.path;
    final manifestPath = '$pluginRoot/install.yaml';
    return File(manifestPath).existsSync() ? manifestPath : null;
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Resolve and parse the manifest.
    final manifestPath = await resolveManifestPath();
    if (manifestPath == null) {
      ctx.output.error(
        'magic_deeplink install.yaml could not be resolved. The plugin asset '
        'bundle is missing or the package was loaded from an unexpected location.',
      );
      return 1;
    }

    final InstallManifest manifest;
    try {
      manifest = ManifestParser.parseFile(manifestPath);
    } on FormatException catch (e) {
      ctx.output.error('install.yaml at $manifestPath: $e');
      return 1;
    } on ManifestValidationException catch (e) {
      ctx.output.error('install.yaml at $manifestPath: ${e.message}');
      return 1;
    }

    // 2. Build the install context and run the manifest installer.
    final installContext = buildContext(ctx);
    final installer = ManifestInstaller(installContext, manifest);
    final result = await installer.install(
      dryRun: isDryRun(ctx),
      force: isForce(ctx),
      nonInteractive: isNonInteractive(ctx),
    );

    // 3. Echo the post_install message on success.
    if (result is Success && manifest.postInstall.message != null) {
      ctx.output.info(manifest.postInstall.message!);
    }

    return result is Success || result is DryRun ? 0 : 1;
  }
}
