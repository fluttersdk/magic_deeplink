import 'dart:io';

import 'package:magic_cli/magic_cli.dart';

import '../helpers/deeplink_config_helper.dart';

/// CLI command to install the deep link configuration file into the project.
///
/// Writes `lib/config/deeplink.dart` to the current working directory.
/// Skips the write if the file already exists unless `--force` is passed.
class InstallCommand extends Command {
  @override
  String get name => 'install';

  @override
  String get description => 'Install deep link configuration.';

  /// {@macro magic_cli.Command.configure}
  @override
  void configure(ArgParser parser) {
    parser.addFlag(
      'force',
      abbr: 'f',
      help: 'Overwrite existing configuration.',
      defaultsTo: false,
    );
  }

  @override
  Future<void> handle() async {
    final force = arguments['force'] as bool? ?? false;

    info('Installing Deep Link configuration (force: $force)...');

    final configContent = DeeplinkConfigHelper.getDeeplinkConfigTemplate();
    final file = File('lib/config/deeplink.dart');

    // 1. Guard: skip if already exists and --force not set.
    if (file.existsSync() && !force) {
      warn('Configuration file already exists. Use --force to overwrite.');
      return;
    }

    // 2. Write the config template to disk.
    await file.create(recursive: true);
    await file.writeAsString(configContent);

    success('Created lib/config/deeplink.dart');
  }
}
