import 'dart:async';

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
  final StreamController<Uri> _linkController =
      StreamController<Uri>.broadcast();
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
  /// Returns true if a handler was found and successfully handled the URI.
  Future<bool> handleUri(Uri uri) async {
    _linkController.add(uri);
    for (final handler in _handlers) {
      if (handler.canHandle(uri)) {
        return await handler.handle(uri);
      }
    }
    return false;
  }
}
