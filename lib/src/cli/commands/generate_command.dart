import 'dart:io';

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
      defaultsTo: 'public',
      help: 'Output directory for generated files (relative to project root).',
    );

    parser.addOption(
      'root',
      defaultsTo: '.',
      help: 'Project root directory (defaults to current working directory).',
    );

    parser.addOption(
      'team-id',
      help: 'Apple Developer Team ID (for AASA).',
    );

    parser.addOption(
      'bundle-id',
      help: 'iOS app bundle identifier.',
    );

    parser.addOption(
      'package-name',
      help: 'Android package name.',
    );

    parser.addMultiOption(
      'sha256-fingerprints',
      help: 'SHA-256 fingerprints.',
    );

    parser.addMultiOption(
      'paths',
      defaultsTo: ['/*'],
      help: 'Paths to handle.',
    );
  }

  @override
  Future<void> handle() async {
    // 1. Read all CLI option values — no defaults live in this method.
    final root = arguments['root'] as String? ?? '.';
    final outputDir = arguments['output'] as String? ?? 'public';
    String teamId = arguments['team-id'] as String? ?? '';
    String bundleId = arguments['bundle-id'] as String? ?? '';
    String packageName = arguments['package-name'] as String? ?? '';
    List<String> fingerprints = arguments['sha256-fingerprints'] as List<String>? ?? [];
    List<String> paths = arguments['paths'] as List<String>? ?? [];

    // 2. Resolve paths for the operation.
    final projectRoot = getProjectRoot();
    final effectiveRoot = root == '.' ? projectRoot : root;
    final outputPath = '$effectiveRoot/$outputDir';

    // 3. Try to read lib/config/deeplink.dart.
    final configFile = File('$effectiveRoot/lib/config/deeplink.dart');
    if (configFile.existsSync()) {
      final content = configFile.readAsStringSync();
      final config = parseDeeplinkConfig(content);

      // 4. Merge: CLI flags override config values.
      if (teamId.isEmpty) {
        teamId = config['teamId'] as String? ?? '';
      }
      if (bundleId.isEmpty) {
        bundleId = config['bundleId'] as String? ?? '';
      }
      if (packageName.isEmpty) {
        packageName = config['packageName'] as String? ?? '';
      }
      if (fingerprints.isEmpty) {
        fingerprints = config['fingerprints'] as List<String>? ?? [];
      }

      // Only use config paths if CLI didn't explicitly provide paths.
      // `paths` has a default value `['/*']` in `configure()`. We only override it
      // if it equals the default AND config has paths.
      if (paths.length == 1 && paths.first == '/*' && (config['paths'] as List<String>? ?? []).isNotEmpty) {
        paths = config['paths'] as List<String>;
      }
    }

    info('Generating deep link files in $outputPath...');

    // 5. Detect iOS platform via PlatformHelper — inform user about AASA placement.
    if (PlatformHelper.hasPlatform(effectiveRoot, 'ios')) {
      info(
        'iOS platform detected — upload apple-app-site-association to your web server root.',
      );
    }

    // 6. Build and write apple-app-site-association (iOS Universal Links).
    if (teamId.isNotEmpty && bundleId.isNotEmpty) {
      final aasaData = buildAppleAppSiteAssociation(teamId, bundleId, paths);
      JsonEditor.writeJson('$outputPath/apple-app-site-association', aasaData);
      success('Created $outputPath/apple-app-site-association');
    } else {
      warn(
        'Skipping apple-app-site-association — provide --team-id and --bundle-id.',
      );
    }

    // 7. Build and write assetlinks.json (Android App Links).
    if (packageName.isNotEmpty && fingerprints.isNotEmpty) {
      final assetLinksData = buildAssetLinks(packageName, fingerprints);
      JsonEditor.writeJson('$outputPath/assetlinks.json', assetLinksData);
      success('Created $outputPath/assetlinks.json');
    } else {
      warn(
        'Skipping assetlinks.json — provide --package-name and --sha256-fingerprints.',
      );
    }
  }

  // -------------------------------------------------------------------------
  // Public parsers and builders (testable independently of file I/O)
  // -------------------------------------------------------------------------

  /// Parse a deep link configuration Dart file content.
  ///
  /// @param content  Raw content of lib/config/deeplink.dart.
  /// @return A map with extracted configuration values.
  Map<String, dynamic> parseDeeplinkConfig(String content) {
    final config = <String, dynamic>{};

    final teamIdMatch = RegExp(r"'team_id':\s*'([^']+)'").firstMatch(content);
    if (teamIdMatch != null) {
      config['teamId'] = teamIdMatch.group(1);
    }

    final bundleIdMatch = RegExp(r"'bundle_id':\s*'([^']+)'").firstMatch(content);
    if (bundleIdMatch != null) {
      config['bundleId'] = bundleIdMatch.group(1);
    }

    final packageNameMatch = RegExp(r"'package_name':\s*'([^']+)'").firstMatch(content);
    if (packageNameMatch != null) {
      config['packageName'] = packageNameMatch.group(1);
    }

    final fingerprintsMatch = RegExp(r"'sha256_fingerprints':\s*\[(.*?)\]", dotAll: true).firstMatch(content);
    if (fingerprintsMatch != null) {
      final fingerprintsContent = fingerprintsMatch.group(1) ?? '';
      final fingerprintMatches = RegExp(r"'([^']+)'").allMatches(fingerprintsContent);
      config['fingerprints'] = fingerprintMatches.map((m) => m.group(1)!).toList();
    }

    final pathsMatch = RegExp(r"'paths':\s*\[(.*?)\]", dotAll: true).firstMatch(content);
    if (pathsMatch != null) {
      final pathsContent = pathsMatch.group(1) ?? '';
      final pathMatches = RegExp(r"'([^']+)'").allMatches(pathsContent);
      config['paths'] = pathMatches.map((m) => m.group(1)!).toList();
    }

    return config;
  }

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
