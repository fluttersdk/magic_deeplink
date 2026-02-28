import 'package:test/test.dart';

// Import via barrel — all CLI symbols must be reachable from this one import.
import 'package:magic_deeplink/src/cli/cli.dart';

void main() {
  group('CLI barrel exports', () {
    test('barrel file can be imported without error', () {
      // The import above compiling is itself proof — this is a sanity guard.
      expect(true, isTrue);
    });

    test('InstallCommand is accessible via barrel', () {
      final command = InstallCommand();
      expect(command, isNotNull);
    });

    test('GenerateCommand is accessible via barrel', () {
      final command = GenerateCommand();
      expect(command, isNotNull);
    });
    test('Kernel is accessible via barrel (re-exported from magic_cli)', () {
      final kernel = Kernel();
      expect(kernel, isNotNull);
    });
  });
}
