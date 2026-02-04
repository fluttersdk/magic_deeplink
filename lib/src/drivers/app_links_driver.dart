import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';
import 'deeplink_driver.dart';

/// Driver implementation using the `app_links` package.
class AppLinksDriver extends DeeplinkDriver {
  /// The app_links instance.
  // ignore: unused_field
  late final AppLinks _appLinks;

  @override
  String get name => 'app_links';

  @override
  bool get isSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

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
    // AppLinks does not require explicit disposal of the instance itself,
    // but we can clean up any local resources if needed.
  }
}
