import 'package:args/command_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_deeplink/src/cli/commands/install_command.dart';

void main() {
  test('install command entry point setup', () {
    final runner = CommandRunner('magic_deeplink_install', 'Install Deep Link configuration');
    runner.addCommand(InstallCommand());

    expect(runner.commands.containsKey('install'), isTrue);
    final command = runner.commands['install']!;
    expect(command.argParser.options.containsKey('force'), isTrue);
  });
}
