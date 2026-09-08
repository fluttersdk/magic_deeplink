import 'dart:async';

import 'package:flutter/foundation.dart';

import 'handlers/deeplink_handler.dart';
import 'drivers/deeplink_driver.dart';
import 'exceptions/deeplink_exception.dart';

/// Manages deep link handling and driver coordination.
class DeeplinkManager {
  static final DeeplinkManager _instance = DeeplinkManager._internal();

  /// Returns the singleton instance of [DeeplinkManager].
  factory DeeplinkManager() => _instance;

  DeeplinkManager._internal();

  final List<DeeplinkHandler> _handlers = [];
  DeeplinkDriver? _driver;
  StreamController<Uri> _linkController = StreamController<Uri>.broadcast();
  Uri? _initialLink;
  bool _initialLinkFetched = false;

  /// Stream of incoming deep links.
  Stream<Uri> get onLink => _linkController.stream;

  /// Returns the current deep link driver.
  /// Throws [DeeplinkException] if no driver is configured.
  DeeplinkDriver get driver {
    if (_driver == null) {
      throw DeeplinkException(
        'No deep link driver configured. Make sure to call setDriver() or register the service provider.',
        code: 'NO_DRIVER',
      );
    }
    return _driver!;
  }

  /// Sets the deep link driver.
  void setDriver(DeeplinkDriver driver) {
    _driver = driver;
  }

  /// Removes the current deep link driver.
  void forgetDriver() {
    _driver = null;
  }

  /// Registers a new deep link handler.
  void registerHandler(DeeplinkHandler handler) {
    if (!_handlers.contains(handler)) {
      _handlers.add(handler);
    }
  }

  /// Checks if the manager has the given handler.
  bool hasHandler(DeeplinkHandler handler) {
    return _handlers.contains(handler);
  }

  /// Removes all registered handlers.
  void forgetHandlers() {
    _handlers.clear();
  }

  /// Returns the initial link that opened the application, if any.
  /// Caches the result after the first call.
  Future<Uri?> getInitialLink() async {
    if (_initialLinkFetched) {
      return _initialLink;
    }

    _initialLink = await driver.getInitialLink();
    _initialLinkFetched = true;
    return _initialLink;
  }

  /// Handles the given URI by delegating to the first matching handler.
  ///
  /// [source] travels with the URI all the way to the handler, because the
  /// decision a handler has to make about a crafted link cannot be made from
  /// the link. [payload] is the whole payload the instruction arrived with,
  /// which only a push has.
  ///
  /// Returns true if a handler was found and successfully handled the URI.
  Future<bool> handleUri(
    Uri uri, {
    required DeeplinkSource source,
    Map<String, dynamic>? payload,
  }) async {
    _linkController.add(uri);
    for (final handler in _handlers) {
      if (handler.canHandle(uri)) {
        return await handler.handle(uri, source: source, payload: payload);
      }
    }
    return false;
  }

  /// Returns this singleton to the state it was constructed in.
  ///
  /// The manager outlives an application in a test binary, and two pieces of
  /// its state outlive [forgetDriver] as well: the cached initial link, which
  /// makes a second [getInitialLink] answer the previous test's URI without
  /// ever reaching the driver, and the broadcast controller behind [onLink],
  /// which nothing has ever closed. Both are dropped here, and [onLink] hands
  /// out a fresh stream afterwards.
  @visibleForTesting
  void reset() {
    forgetHandlers();
    forgetDriver();

    _initialLink = null;
    _initialLinkFetched = false;

    unawaited(_linkController.close());
    _linkController = StreamController<Uri>.broadcast();
  }
}
