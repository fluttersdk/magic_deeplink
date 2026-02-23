import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:magic_cli/magic_cli.dart' hide Command;
import '../helpers/deeplink_config_helper.dart';

class InstallCommand extends Command {
  @override
  final String name = 'install';

  @override
  final String description = 'Install deep link configuration.';

  InstallCommand() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Overwrite existing configuration.',
      defaultsTo: false,
    );
  }

  @override
  Future<void> run() async {
    // In a real implementation, this would write the file to the project.
    // We are mocking the CLI environment here.
    final force = argResults?['force'] as bool? ?? false;
    // ignore: avoid_print
    print(ConsoleStyle.info('Installing Deep Link configuration (force: $force)...'));

    final configContent = DeeplinkConfigHelper.getDeeplinkConfigTemplate();
    final file = File('lib/config/deeplink.dart');

    if (await file.exists() && !force) {
      // ignore: avoid_print
      print(ConsoleStyle.warning('Configuration file already exists. Use --force to overwrite.'));
      return;
    }

    await file.create(recursive: true);
    await file.writeAsString(configContent);

    // ignore: avoid_print
    print(ConsoleStyle.success('Created lib/config/deeplink.dart'));
  }
}
