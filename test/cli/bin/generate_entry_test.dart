import 'package:args/command_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_deeplink/src/cli/commands/generate_command.dart';

void main() {
  test('generate command entry point setup', () {
    final runner = CommandRunner('magic_deeplink_generate', 'Generate Deep Link configuration');
    runner.addCommand(GenerateCommand());

    expect(runner.commands.containsKey('generate'), isTrue);
    final command = runner.commands['generate']!;
    expect(command.argParser.options.containsKey('output'), isTrue);
  });
}
