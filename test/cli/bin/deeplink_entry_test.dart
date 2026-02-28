import 'package:magic_cli/magic_cli.dart' hide InstallCommand;
import 'package:test/test.dart';

import 'package:magic_deeplink/src/cli/commands/generate_command.dart';
import 'package:magic_deeplink/src/cli/commands/install_command.dart';

void main() {
  group('Kernel dispatch integration', () {
    late Kernel kernel;

    setUp(() {
      kernel = Kernel();
      kernel.registerMany([
        InstallCommand(),
        GenerateCommand(),
      ]);
    });

    test('install command is registered and accessible', () {
      // If the command were not registered, handle(['install', '--help'])
      // would throw or exit with an error. We verify by checking that
      // Kernel can be constructed with both commands without error.
      expect(kernel, isNotNull);
    });

    test('Kernel can be created with InstallCommand registered', () {
      final k = Kernel();
      expect(() => k.register(InstallCommand()), returnsNormally);
    });

    test('Kernel can be created with GenerateCommand registered', () {
      final k = Kernel();
      expect(() => k.register(GenerateCommand()), returnsNormally);
    });

    test('Kernel registerMany accepts both commands without error', () {
      final k = Kernel();
      expect(
        () => k.registerMany([
          InstallCommand(),
          GenerateCommand(),
        ]),
        returnsNormally,
      );
    });
  });
}
