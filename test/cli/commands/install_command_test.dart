import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_deeplink/src/cli/commands/install_command.dart';

void main() {
  group('InstallCommand', () {
    test('has correct name and description', () {
      final command = InstallCommand();
      expect(command.name, 'install');
      expect(command.description, contains('Install deep link configuration'));
    });

    test('accepts force option', () {
      final command = InstallCommand();
      expect(command.argParser.options.containsKey('force'), isTrue);
    });
  });
}
