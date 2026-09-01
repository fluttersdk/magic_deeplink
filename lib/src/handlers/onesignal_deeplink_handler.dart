import 'dart:async';

import 'package:magic/magic.dart';

import '../deeplink_manager.dart';

/// **Turns a tapped push notification into a deep link.**
///
/// The bridge between `magic_notifications` and this package, and the only
/// place that knows the shape of the other package. That coupling is
/// deliberately structural: `magic_notifications` is an OPTIONAL companion, so
/// nothing here imports it, names its types, or casts to them. The manager is
/// taken as [dynamic], its click stream is read by name, and each event's
/// payload is read off the event the same way.
///
/// The previous version cast the stream to `Stream<Map<String, dynamic>>`,
/// which the real one has never been, so every push click threw instead of
/// routing.
///
/// ### Example Usage:
/// ```dart
/// if (app.bound('notifications')) {
///   OneSignalDeeplinkHandler().setup(manager, app.make('notifications'));
/// }
/// ```
class OneSignalDeeplinkHandler {
  /// The container key magic binds its log manager under.
  static const String _logBinding = 'log';

  /// The member a notification manager publishes tapped pushes on.
  static const String _clickStream = 'onPushClicked';

  StreamSubscription<dynamic>? _subscription;

  /// Extract URI from OneSignal notification data
  ///
  /// Checks for common keys: 'url', 'deep_link', 'link', 'uri'
  Uri? extractUri(Map<String, dynamic>? data) {
    if (data == null) return null;

    final keys = ['url', 'deep_link', 'link', 'uri'];

    for (final key in keys) {
      if (data.containsKey(key)) {
        final value = data[key];
        if (value is String && value.isNotEmpty) {
          return Uri.tryParse(value);
        }
      }
    }

    return null;
  }

  /// The payload carried by a push click [event], or `null` when it carries
  /// none that a deep link can be read from.
  ///
  /// Read structurally: the event class lives in `magic_notifications` and this
  /// package must not depend on it, so the payload is taken off a `data` member
  /// without the type behind it ever being named. What comes back is the
  /// server's own payload, flat, on both mobile and web.
  ///
  /// An event that carries no readable payload is REPORTED and skipped. It
  /// means the two packages disagree about the event shape, which is exactly
  /// the failure that went unnoticed here for a whole release.
  Map<String, dynamic>? extractData(dynamic event) {
    if (event == null) return null;

    final dynamic data;

    try {
      data = event.data;
    } on NoSuchMethodError {
      _report(
        'A push click event of type ${event.runtimeType} carries no `data` '
        'payload, so no deep link could be read from it.',
      );

      return null;
    }

    if (data is Map<String, dynamic>) return data;

    _report(
      'A push click payload of type ${data.runtimeType} is not a '
      'Map<String, dynamic>, so no deep link could be read from it.',
    );

    return null;
  }

  /// Route the pushes tapped on [notifications] into [manager].
  ///
  /// [notifications] is `magic_notifications`' notification manager, resolved
  /// out of magic's container by the consumer and read structurally here.
  ///
  /// It is the MANAGER's click stream that is subscribed to, never the push
  /// driver's, and that is what makes this independent of provider order: the
  /// manager republishes clicks on a broadcast stream it owns from
  /// construction, so a driver attached later by the notifications provider's
  /// own `boot` still reaches this subscription. The stream is also the guarded
  /// one, so a push addressed to whoever held the device before does not open a
  /// deep link for whoever holds it now.
  void setup(DeeplinkManager manager, dynamic notifications) {
    final Stream<dynamic>? clicks = _resolveClickStream(notifications);

    // Cancelled before the null check, not after it. A second `setup` whose
    // manager publishes no click stream still supersedes the first, and leaving
    // the previous subscription live there would route taps through a manager
    // this handler was just told to stop following.
    _subscription?.cancel();
    _subscription = null;

    if (clicks == null) return;

    _subscription = clicks.listen(
      (event) => _route(manager, event),
      onError: (Object error) => _report(
        'The push click stream failed, so a tapped notification may not have '
        'opened its deep link: $error',
      ),
    );
  }

  /// Dispose the subscription
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// The stream [notifications] publishes tapped pushes on, or `null` when it
  /// publishes none.
  ///
  /// Both absences are reported rather than swallowed: a manager without the
  /// stream means the companion package is older than this wiring expects, and
  /// either way push clicks silently stop opening deep links.
  Stream<dynamic>? _resolveClickStream(dynamic notifications) {
    final dynamic published;

    try {
      published = notifications.onPushClicked;
    } on NoSuchMethodError {
      _report(
        'The bound `notifications` manager of type '
        '${notifications.runtimeType} publishes no `$_clickStream` stream, so '
        'a tapped push notification cannot open a deep link. Upgrade '
        'magic_notifications to a version whose NotificationManager exposes '
        'it.',
      );

      return null;
    }

    if (published is Stream) return published;

    _report(
      'The bound `notifications` manager exposes `$_clickStream` as a '
      '${published.runtimeType} rather than a Stream, so a tapped push '
      'notification cannot open a deep link.',
    );

    return null;
  }

  /// Hand the deep link carried by [event], if any, to [manager].
  void _route(DeeplinkManager manager, dynamic event) {
    final Map<String, dynamic>? data = extractData(event);

    if (data == null) return;

    final Uri? uri = extractUri(data);

    // A push that carries no link is the ordinary case, not a failure: most
    // notifications are meant to be read, not navigated to.
    if (uri == null) return;

    manager.handleUri(uri);
  }

  /// Report [message] at error level, when the host has a log to report to.
  ///
  /// [Log] resolves `log` out of magic's container and THROWS when nothing
  /// bound it, and an app that registers no logging provider is a legitimate
  /// build. Asking first is the same idiom `magic_notifications` uses in its
  /// own `NotificationLog`, and it keeps a diagnostic from becoming a second
  /// failure on a path that is already degrading.
  void _report(String message) {
    if (!Magic.bound(_logBinding)) return;

    Log.error('[deeplink] $message');
  }
}
