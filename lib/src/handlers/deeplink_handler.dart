/// Where a deep link instruction came from.
///
/// The two paths into a handler are not equally trusted and a handler cannot
/// tell them apart from the URI: an [osLink] is whatever the operating system
/// was asked to open, so anyone who can send the device a link can craft one,
/// while a [push] payload was authored by the server that sent the
/// notification. A consumer that acts on more than the path (switching teams
/// off a `team_id` key, say) reads this to decide whether it may.
enum DeeplinkSource {
  /// The operating system opened the app on a Universal Link or App Link.
  ///
  /// Attacker-craftable: treat the URI as untrusted input.
  osLink,

  /// The user tapped a push notification, and the payload is the server's own.
  push,

  /// The application asked for the link itself, in code or in a test.
  manual,
}

/// Abstract class defining a handler for deep links.
abstract class DeeplinkHandler {
  /// Checks if this handler can handle the given URI.
  bool canHandle(Uri uri);

  /// Handles [uri] and returns whether it was handled.
  ///
  /// [source] is required rather than defaulted because a handler that forgot
  /// to ask would treat a crafted OS link exactly like a server-authored push.
  /// [payload] carries the whole payload the push was delivered with, and is
  /// null on every path that has no payload behind it.
  ///
  /// Implementations do NOT throw: a link this handler cannot route answers
  /// false so the manager can try the next one.
  Future<bool> handle(
    Uri uri, {
    required DeeplinkSource source,
    Map<String, dynamic>? payload,
  });
}
