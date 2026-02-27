import 'package:magic_cli/magic_cli.dart' hide InstallCommand;
import 'package:magic_deeplink/src/cli/commands/generate_command.dart';
import 'package:magic_deeplink/src/cli/commands/install_command.dart';

/// Entry point for the `deeplink` CLI tool.
///
/// Bootstraps a [Kernel] with both available commands and delegates
/// argument handling to the kernel's dispatcher.
void main(List<String> args) async {
  final kernel = Kernel();

  kernel.registerMany([
    InstallCommand(),
    GenerateCommand(),
  ]);

  await kernel.handle(args);
}
