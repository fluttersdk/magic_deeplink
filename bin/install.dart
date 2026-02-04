import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:fluttersdk_magic_cli/fluttersdk_magic_cli.dart' hide Command;
import 'package:fluttersdk_magic_deeplink/src/cli/commands/install_command.dart';

void main(List<String> args) async {
  final runner = CommandRunner<void>(
    'magic_deeplink:install',
    'Install Deep Link configuration.',
  )
    ..addCommand(InstallCommand());

  try {
    await runner.run(['install', ...args]);
  } on UsageException catch (e) {
    // ignore: avoid_print
    print(e);
    exit(64);
  } catch (e) {
    // ignore: avoid_print
    print(ConsoleStyle.error(e.toString()));
    exit(1);
  }
}
