import 'package:fluttersdk_artisan/artisan.dart';

import 'commands/doctor_command.dart' as deeplink_doctor;
import 'commands/generate_command.dart';
import 'commands/install_command.dart';

/// Artisan provider that registers all magic_deeplink CLI commands.
class MagicDeeplinkArtisanProvider extends ArtisanServiceProvider {
  @override
  String get providerName => 'magic_deeplink';

  @override
  List<ArtisanCommand> commands() => <ArtisanCommand>[
        InstallCommand(),
        GenerateCommand(),
        deeplink_doctor.DoctorCommand(),
      ];
}
