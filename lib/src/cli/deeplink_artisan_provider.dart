import 'package:fluttersdk_artisan/artisan.dart';

import 'commands/generate_command.dart';
import 'commands/install_command.dart';

/// Artisan provider that registers all magic_deeplink CLI commands.
class DeeplinkArtisanProvider extends ArtisanServiceProvider {
  @override
  String get providerName => 'magic_deeplink';

  @override
  List<ArtisanCommand> commands() => <ArtisanCommand>[
        InstallCommand(),
        GenerateCommand(),
      ];
}
