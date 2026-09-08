import 'dart:io';

import 'package:app_links/app_links.dart';

import 'deeplink_driver.dart';

/// `dart:io` arm of the platform trio: Android, iOS, macOS, and any other
/// target where `dart:io` resolves.
///
/// Delegates to the `app_links` package for both the initial link and the
/// live link stream; it is the only arm of the three that talks to a real
/// platform channel.
class AppLinksDriver extends DeeplinkDriver {
  /// The `app_links` package instance, created in [initialize].
  late final AppLinks _appLinks;

  @override
  String get name => 'app_links';

  /// No try/catch: this file compiles only where `dart.library.io` resolves,
  /// so `Platform` is real here and these getters cannot throw. The guard this
  /// replaced existed to survive the web build, and the web arm now takes that
  /// case instead.
  @override
  bool get isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _appLinks = AppLinks();
  }

  @override
  Future<Uri?> getInitialLink() async {
    try {
      return await _appLinks.getInitialLink();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<Uri> get onLink => _appLinks.uriLinkStream;

  @override
  void dispose() {
    // AppLinks does not require explicit disposal of the instance itself.
  }
}
