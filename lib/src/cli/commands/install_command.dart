import 'package:magic_cli/magic_cli.dart';

import '../helpers/deeplink_config_helper.dart';

/// CLI command to install the deep link configuration file into the project.
///
/// Writes `lib/config/deeplink.dart` to the current working directory.
/// Skips the write if the file already exists unless `--force` is passed.
///
/// ## Usage
///
/// ```bash
/// dart run magic_deeplink install
/// dart run magic_deeplink install --force
/// ```
class InstallCommand extends Command {
  @override
  String get name => 'install';

  @override
  String get description => 'Install deep link configuration.';

  /// Return the Flutter project root directory.
  ///
  /// Overridable in tests to point at a temp directory without requiring
  /// a real pubspec.yaml to be present on disk.
  String getProjectRoot() {
    return FileHelper.findProjectRoot();
  }

  @override
  void configure(ArgParser parser) {
    parser.addFlag(
      'force',
      abbr: 'f',
      help: 'Overwrite existing configuration file.',
      defaultsTo: false,
      negatable: false,
    );
  }

  @override
  Future<void> handle() async {
    // 1. Read CLI flags before doing any file work.
    final force = arguments['force'] as bool? ?? false;
    final root = getProjectRoot();
    final configPath = '$root/lib/config/deeplink.dart';

    info('Installing deep link configuration...');

    // 2. Guard: skip write when the config already exists and --force is absent.
    //    Prevents accidental overwrites of customised configs.
    if (FileHelper.fileExists(configPath) && !force) {
      warn('Configuration file already exists. Use --force to overwrite.');
      return;
    }

    // 3. Fetch the standardised template and write it to disk.
    //    FileHelper.writeFile creates parent directories automatically.
    final configContent = DeeplinkConfigHelper.getDeeplinkConfigTemplate();
    FileHelper.writeFile(configPath, configContent);

    success('Created lib/config/deeplink.dart');
  }
}
