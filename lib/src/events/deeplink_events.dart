import 'package:magic/magic.dart';

import '../handlers/deeplink_handler.dart';

/// Dispatched when `RouteDeeplinkHandler` starts opening a link it claimed,
/// before any tenant switch or navigation.
///
/// It exists for the crash reporter's breadcrumb trail: a cold tap that ends
/// on a broken page leaves no screen to read a log on, and [source] is what
/// tells the cold-start shape (a push replayed while the app is still
/// starting) from an OS link that arrived after the first frame.
///
/// [breadcrumbData] carries the matched route PATTERN and two flags, never
/// the concrete path, the query or a payload value: a link can carry an invite
/// or reset token in any of them (`/invitations/:token/accept`), and a
/// breadcrumb rides along with every event the session sends afterwards.
class DeeplinkOpened extends MagicEvent implements ReportsBreadcrumb {
  /// Where the link came from.
  final DeeplinkSource source;

  /// The handler's path pattern the link matched (`/incidents/:id`), not the
  /// link's own path.
  final String route;

  /// Whether the payload named a tenant under the gate's payload key. Always
  /// false for a handler that has no tenant gate.
  final bool namesTenant;

  DeeplinkOpened({
    required this.source,
    required this.route,
    required this.namesTenant,
  });

  @override
  String get breadcrumbCategory => 'deeplink.open';

  @override
  String get breadcrumbMessage => 'an external link is being opened';

  @override
  Map<String, Object?> get breadcrumbData => <String, Object?>{
        'source': source.name,
        'route': route,
        'names_tenant': namesTenant,
      };
}

/// Dispatched immediately before `RouteDeeplinkHandler` hands a link's path to
/// the router.
///
/// The ordering is the value: an exception thrown while the destination
/// builds carries this as its last breadcrumb, which separates "the link
/// never resolved" from "the link resolved and the page it named threw".
class DeeplinkNavigating extends MagicEvent implements ReportsBreadcrumb {
  /// The handler's path pattern the link matched, for the same reason
  /// [DeeplinkOpened.route] is not the concrete path.
  final String route;

  DeeplinkNavigating({required this.route});

  @override
  String get breadcrumbCategory => 'deeplink.navigate';

  @override
  String get breadcrumbMessage =>
      'navigating to a destination named by an external link';

  @override
  Map<String, Object?> get breadcrumbData => <String, Object?>{
        'route': route,
      };
}
