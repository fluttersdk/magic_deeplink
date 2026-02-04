import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:fluttersdk_magic_cli/fluttersdk_magic_cli.dart' hide Command;
import 'package:fluttersdk_magic_deeplink/src/cli/commands/generate_command.dart';

void main(List<String> args) async {
  final runner = CommandRunner<void>(
    'magic_deeplink:generate',
    'Generate Deep Link configuration files.',
  )
    ..addCommand(GenerateCommand());

  try {
    await runner.run(['generate', ...args]);
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
