import 'deeplink_driver.dart';

/// `dart:js_interop` arm of the platform trio: the browser.
///
/// Deliberately inert rather than wired to `app_links_web`: that package
/// reads the boot-time `location.href` once and never reacts to later
/// navigation, while GoRouter already owns the address bar under this app's
/// path strategy, so routing it again here would be a duplicate. Every
/// member still answers rather than throwing, so a caller that has not
/// checked [isSupported] gets an empty result instead of a crash.
class AppLinksDriver extends DeeplinkDriver {
  @override
  String get name => 'app_links';

  @override
  bool get isSupported => false;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}

  @override
  Future<Uri?> getInitialLink() async => null;

  @override
  Stream<Uri> get onLink => const Stream<Uri>.empty();

  @override
  void dispose() {}
}
