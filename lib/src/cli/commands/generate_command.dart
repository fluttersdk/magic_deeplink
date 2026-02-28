import 'package:magic_cli/magic_cli.dart';

/// CLI command to generate deep link server-side configuration files.
///
/// Produces `apple-app-site-association` (iOS Universal Links) and
/// `assetlinks.json` (Android App Links) from values supplied as CLI options.
/// No hardcoded values — all config must be passed via flags.
///
/// ## Usage
///
/// ```bash
/// dart run magic_deeplink generate \
///   --team-id ABCDE12345 \
///   --bundle-id your.package.name \
///   --package-name your.package.name \
///   --sha256-fingerprints AA:BB:CC:... \
///   --output public
/// ```
class GenerateCommand extends Command {
  @override
  String get name => 'generate';

  @override
  String get description =>
      'Generate deep link configuration files (apple-app-site-association, assetlinks.json).';

  /// Return the Flutter project root directory.
  ///
  /// Overridable in tests to use a temp directory.
  String getProjectRoot() {
    return FileHelper.findProjectRoot();
  }

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'output',
      abbr: 'o',
      help: 'Output directory for generated files (relative to project root).',
      defaultsTo: 'public',
    );

    parser.addOption(
      'root',
      help: 'Project root directory (defaults to current working directory).',
      defaultsTo: '.',
    );

    parser.addOption(
      'team-id',
      help: 'Apple Developer Team ID — used for apple-app-site-association.',
    );

    parser.addOption(
      'bundle-id',
      help: 'iOS app bundle identifier — used for apple-app-site-association.',
    );

    parser.addOption(
      'package-name',
      help: 'Android package name — used for assetlinks.json.',
    );

    parser.addMultiOption(
      'sha256-fingerprints',
      help: 'SHA-256 certificate fingerprints — used for assetlinks.json.',
    );

    parser.addMultiOption(
      'paths',
      help: 'Universal Link / App Link paths to register.',
      defaultsTo: ['/*'],
    );
  }

  @override
  Future<void> handle() async {
    // 1. Read all CLI option values — no defaults live in this method.
    final root = getProjectRoot();
    final outputDir = arguments['output'] as String? ?? 'public';
    final teamId = arguments['team-id'] as String? ?? '';
    final bundleId = arguments['bundle-id'] as String? ?? '';
    final packageName = arguments['package-name'] as String? ?? '';
    final fingerprints =
        arguments['sha256-fingerprints'] as List<String>? ?? [];
    final paths = arguments['paths'] as List<String>? ?? ['/*'];

    final outputPath = '$root/$outputDir';

    info('Generating deep link files in $outputPath...');

    // 2. Detect iOS platform via PlatformHelper — inform user about AASA placement.
    if (PlatformHelper.hasPlatform(root, 'ios')) {
      info(
          'iOS platform detected — upload apple-app-site-association to your web server root.');
    }

    // 3. Build and write apple-app-site-association (iOS Universal Links).
    if (teamId.isNotEmpty && bundleId.isNotEmpty) {
      final aasaData = buildAppleAppSiteAssociation(teamId, bundleId, paths);
      JsonEditor.writeJson('$outputPath/apple-app-site-association', aasaData);
      success('Created $outputPath/apple-app-site-association');
    } else {
      warn(
          'Skipping apple-app-site-association — provide --team-id and --bundle-id.');
    }

    // 4. Build and write assetlinks.json (Android App Links).
    if (packageName.isNotEmpty && fingerprints.isNotEmpty) {
      final assetLinksData = buildAssetLinks(packageName, fingerprints);
      JsonEditor.writeJson('$outputPath/assetlinks.json', assetLinksData);
      success('Created $outputPath/assetlinks.json');
    } else {
      warn(
          'Skipping assetlinks.json — provide --package-name and --sha256-fingerprints.');
    }
  }

  // -------------------------------------------------------------------------
  // Public JSON builders (testable independently of file I/O)
  // -------------------------------------------------------------------------

  /// Build the apple-app-site-association JSON map for iOS Universal Links.
  ///
  /// @param teamId    Apple Developer Team ID.
  /// @param bundleId  iOS app bundle identifier.
  /// @param paths     Universal Link paths to register (e.g. `['/*']`).
  /// @return A [Map<String, dynamic>] ready for JSON serialisation.
  Map<String, dynamic> buildAppleAppSiteAssociation(
    String teamId,
    String bundleId,
    List<String> paths,
  ) {
    return {
      'applinks': {
        'apps': <dynamic>[],
        'details': [
          {
            'appID': '$teamId.$bundleId',
            'paths': paths,
          },
        ],
      },
    };
  }

  /// Build the assetlinks.json list for Android App Links.
  ///
  /// Produces one entry per fingerprint — each entry grants `handle_all_urls`
  /// permission to the specified [packageName] with the given certificate.
  ///
  /// @param packageName   Android app package name.
  /// @param fingerprints  List of SHA-256 certificate fingerprints.
  /// @return A [List<dynamic>] ready for JSON serialisation.
  List<dynamic> buildAssetLinks(
    String packageName,
    List<String> fingerprints,
  ) {
    return fingerprints.map((fingerprint) {
      return {
        'relation': [
          'delegate_permission/common.handle_all_urls',
        ],
        'target': {
          'namespace': 'android_app',
          'package_name': packageName,
          'sha256_cert_fingerprints': [fingerprint],
        },
      };
    }).toList();
  }
}
