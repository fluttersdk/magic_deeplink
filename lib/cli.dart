/// Flutter-free artisan-CLI surface for magic_deeplink.
///
/// Exposes ONLY the artisan-CLI surface (MagicDeeplinkArtisanProvider + the
/// CLI commands). Does NOT export magic_deeplink runtime (no Flutter dart:ui
/// imports), so this barrel is safe for consumption from pure-Dart artisan
/// dispatchers.
///
/// Consumers register the provider in their `bin/artisan.dart`:
///
/// ```dart
/// import 'package:fluttersdk_artisan/artisan.dart';
/// import 'package:magic_deeplink/cli.dart' show MagicDeeplinkArtisanProvider;
///
/// Future<void> main(List<String> args) async {
///   final registry = ArtisanRegistry()
///     ..registerProvider(MagicDeeplinkArtisanProvider());
///   exit(await ArtisanApplication(registry: registry).dispatch(args));
/// }
/// ```
///
/// Runtime consumers (lib/main.dart of a Magic-based app) continue to
/// import `package:magic_deeplink/magic_deeplink.dart` for the full surface.
library;

export 'src/cli/commands/generate_command.dart';
export 'src/cli/commands/install_command.dart';
export 'src/cli/deeplink_artisan_provider.dart';
