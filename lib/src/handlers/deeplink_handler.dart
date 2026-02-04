/// Abstract class defining a handler for deep links
abstract class DeeplinkHandler {
  /// Checks if this handler can handle the given URI
  bool canHandle(Uri uri);

  /// Handles the URI
  /// Returns true if the URI was handled successfully
  Future<bool> handle(Uri uri);
}
