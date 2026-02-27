import 'dart:io';

import 'package:magic_cli/magic_cli.dart';

/// CLI command to generate deep link configuration files.
///
/// Produces `apple-app-site-association` (iOS) and `assetlinks.json` (Android)
/// by reading the project's deeplink config and writing JSON files to the
/// specified output directory via [JsonEditor.writeJson].
class GenerateCommand extends Command {
  @override
  String get name => 'generate';

  @override
  String get description =>
      'Generate deep link configuration files (apple-app-site-association, assetlinks.json).';

  /// {@macro magic_cli.Command.configure}
  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'output',
      abbr: 'o',
      help: 'The output directory for generated files.',
      defaultsTo: 'public',
    );
    parser.addOption(
      'root',
      help: 'The project root directory.',
      defaultsTo: '.',
    );
  }

  @override
  Future<void> handle() async {
    final rootDir = arguments['root'] as String? ?? '.';
    final outputDir = arguments['output'] as String? ?? 'public';

    final projectPath = Directory(rootDir).absolute.path;
    final outputPath = '$projectPath/$outputDir';

    info('Generating deep link files in $outputPath...');

    // 1. Detect iOS platform and report path via PlatformHelper.
    if (PlatformHelper.hasPlatform(projectPath, 'ios')) {
      final infoPlistPath = PlatformHelper.infoPlistPath(projectPath);
      info('iOS platform detected — Info.plist at: $infoPlistPath');
    } else {
      warn(
          'iOS platform not detected — skipping apple-app-site-association hint.');
    }

    // 2. Verify deeplink config exists before generating.
    final configPath = '$projectPath/lib/config/deeplink.dart';
    if (!File(configPath).existsSync()) {
      error('Config file not found: $configPath');
      error('Run "deeplink install" first to generate the config.');
      return;
    }

    info('Config found — writing output files to $outputPath...');

    // 3. Generate and write apple-app-site-association.
    final appleAasaMap = _buildAppleAppSiteAssociation(
      teamId: 'YOUR_TEAM_ID',
      bundleId: 'com.example.app',
      paths: ['/*'],
    );
    JsonEditor.writeJson(
        '$outputPath/apple-app-site-association', appleAasaMap);
    success('Created $outputPath/apple-app-site-association');

    // 4. Generate and write assetlinks.json.
    final assetLinksList = _buildAssetLinks(
      packageName: 'com.example.app',
      fingerprints: ['YOUR_SHA256_FINGERPRINT'],
    );
    JsonEditor.writeJson('$outputPath/assetlinks.json', assetLinksList);
    success('Created $outputPath/assetlinks.json');
  }

  // -------------------------------------------------------------------------
  // Builders
  // -------------------------------------------------------------------------

  /// Build the apple-app-site-association JSON map.
  ///
  /// @param teamId    Apple Developer Team ID.
  /// @param bundleId  iOS app bundle identifier.
  /// @param paths     Universal Link paths to handle.
  /// @return A [Map<String, dynamic>] ready for JSON serialisation.
  Map<String, dynamic> _buildAppleAppSiteAssociation({
    required String teamId,
    required String bundleId,
    required List<String> paths,
  }) {
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

  /// Build the assetlinks.json list.
  ///
  /// @param packageName   Android app package name.
  /// @param fingerprints  List of SHA-256 certificate fingerprints.
  /// @return A [List<dynamic>] ready for JSON serialisation.
  List<dynamic> _buildAssetLinks({
    required String packageName,
    required List<String> fingerprints,
  }) {
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
