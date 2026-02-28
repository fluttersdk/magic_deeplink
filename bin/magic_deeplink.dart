import 'package:magic_cli/magic_cli.dart' hide InstallCommand;
import 'package:magic_deeplink/src/cli/commands/generate_command.dart';
import 'package:magic_deeplink/src/cli/commands/install_command.dart';

/// Magic Deeplink CLI entry point.
void main(List<String> args) async {
  final kernel = Kernel();

  // 1. Register deeplink specific commands.
  kernel.registerMany([
    InstallCommand(),
    GenerateCommand(),
  ]);

  // 2. Execute requested command.
  await kernel.handle(args);
}
