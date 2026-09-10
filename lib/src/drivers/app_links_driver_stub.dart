import 'deeplink_driver.dart';

/// Default arm of the platform trio, resolved only when neither the
/// `dart:js_interop` guard (web) nor the `dart:io` guard (native) matches.
///
/// No shipped Flutter build target reaches this arm. It answers the same
/// way as the web arm rather than throwing, because an arm this package has
/// never seen a build target land on is exactly the arm that should not
/// crash the caller that reaches it anyway.
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
