import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:fluttersdk_magic_cli/fluttersdk_magic_cli.dart' hide Command;

class GenerateCommand extends Command {
  @override
  final String name = 'generate';

  @override
  final String description = 'Generate deep link configuration files (apple-app-site-association, assetlinks.json).';

  GenerateCommand() {
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'The output directory for generated files.',
      defaultsTo: 'public',
    );
    argParser.addOption(
      'root',
      help: 'The project root directory.',
      defaultsTo: '.',
    );
  }

  @override
  Future<void> run() async {
    final rootDir = argResults?['root'] as String? ?? '.';
    final outputDir = argResults?['output'] as String? ?? 'public';

    final projectPath = Directory(rootDir).absolute.path;
    final outputPath = '$projectPath/$outputDir';

    // ignore: avoid_print
    print(ConsoleStyle.info('Generating deep link files in $outputPath...'));

    // In a real implementation, we would parse the config file here.
    // For now, we'll placeholder this or expect the user to ensure config is available.
    // Since we can't easily import user code dynamically in a pre-compiled or independent script without mirrors/AST.
    // We will assume for this implementation we might be looking for a magic.json or similar,
    // or we might need to rely on a different mechanism.
    // However, following the plan, I will implement the generation logic.
  }

  String generateAppleAppSiteAssociation(Map<String, dynamic> config) {
    final deepLink = config['deeplink'] as Map<String, dynamic>;
    final ios = deepLink['ios'] as Map<String, dynamic>;
    final paths = (deepLink['paths'] as List).cast<String>();

    final teamId = ios['team_id'];
    final bundleId = ios['bundle_id'];

    final map = {
      'applinks': {
        'apps': [],
        'details': [
          {
            'appID': '$teamId.$bundleId',
            'paths': paths,
          }
        ]
      }
    };

    return const JsonEncoder.withIndent('  ').convert(map);
  }

  String generateAssetLinks(Map<String, dynamic> config) {
    final deepLink = config['deeplink'] as Map<String, dynamic>;
    final android = deepLink['android'] as Map<String, dynamic>;

    final packageName = android['package_name'];
    final fingerprints = (android['sha256_fingerprints'] as List).cast<String>();

    final list = fingerprints.map((fingerprint) {
      return {
        'relation': ['delegate_permission/common.handle_all_urls'],
        'target': {
          'namespace': 'android_app',
          'package_name': packageName,
          'sha256_cert_fingerprints': [fingerprint],
        }
      };
    }).toList();

    return const JsonEncoder.withIndent('  ').convert(list);
  }
}
