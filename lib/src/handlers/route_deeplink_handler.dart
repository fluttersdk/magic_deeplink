import 'package:magic/magic.dart';
import 'package:magic_deeplink/src/handlers/deeplink_handler.dart';

class RouteDeeplinkHandler extends DeeplinkHandler {
  final List<String> paths;

  /// Hosts this handler is allowed to claim an absolute URI for.
  ///
  /// `null` (the default) keeps the original path-only behaviour: any host
  /// matching one of [paths] is claimed. When set, [canHandle] additionally
  /// requires an absolute URI to name one of these hosts (case-insensitively)
  /// over a plain `http`/`https` scheme with no explicit port and no
  /// userinfo, mirroring the check the OS already ran before handing this
  /// app a Universal/App Link. A relative URI (a push payload path, which
  /// carries no scheme and no authority) is always accepted regardless.
  final List<String>? hosts;

  /// Whether path matching treats letter case as significant.
  ///
  /// [hosts] are always compared case-insensitively, whatever this says:
  /// host names are case-insensitive by spec.
  ///
  /// Defaults to `false`, which keeps the original behaviour: go_router
  /// routes are case-sensitive by default, so a consumer that mounted
  /// `/incidents/:id` and set this to `true` stops `/INCIDENTS/5` from being
  /// claimed and then landing on go_router's not-found page.
  final bool caseSensitive;

  final List<RegExp> _patterns;

  RouteDeeplinkHandler({
    required this.paths,
    this.hosts,
    this.caseSensitive = false,
  }) : _patterns = paths.map((p) => _compilePattern(p, caseSensitive)).toList();

  static RegExp _compilePattern(String pattern, bool caseSensitive) {
    // Escape special regex characters except *
    var regex = pattern.replaceAllMapped(
      RegExp(r'[.+^${}()|[\]\\]'),
      (match) => '\\${match.group(0)}',
    );

    // Replace * with .* (match anything)
    regex = regex.replaceAll('*', '.*');

    // Replace :param with [^/]+ (match segment)
    regex = regex.replaceAll(RegExp(r':\w+'), '[^/]+');

    // Ensure full match
    return RegExp('^$regex\$', caseSensitive: caseSensitive);
  }

  @override
  bool canHandle(Uri uri) {
    if (!_addressesAllowedHost(uri)) return false;

    String path = uri.path;

    // Normalize path: remove trailing slash unless it's just "/"
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    return _patterns.any((p) => p.hasMatch(path));
  }

  /// Whether [uri] is on a host this handler is allowed to claim.
  ///
  /// A no-op (always true) when [hosts] is null, which is what keeps the
  /// default behaviour unchanged. When [hosts] is set, a relative URI is
  /// always accepted (it carries no host to check), and an absolute URI is
  /// accepted only over `http`/`https`, with no explicit port and no
  /// userinfo, and only when its host equals one of [hosts]
  /// case-insensitively. A blank entry in [hosts] is ignored rather than
  /// treated as a wildcard: `hosts: ['']` refuses every absolute URI,
  /// including one whose own host is empty (`https:/incidents/5`), instead
  /// of matching it on the empty string.
  bool _addressesAllowedHost(Uri uri) {
    final List<String>? allowedHosts = hosts;
    if (allowedHosts == null) return true;
    if (!uri.hasScheme && !uri.hasAuthority) return true;

    if (uri.scheme != 'https' && uri.scheme != 'http') return false;
    if (uri.hasPort || uri.userInfo.isNotEmpty) return false;

    final String host = uri.host.toLowerCase();
    return allowedHosts
        .where((h) => h.isNotEmpty)
        .any((h) => h.toLowerCase() == host);
  }

  /// Navigates to the path [uri] names.
  ///
  /// [source] and [payload] are deliberately unused: routing to a path the
  /// consumer listed is safe whoever asked for it. A handler that acts on the
  /// payload is the consumer's to write, and it is the one that reads [source].
  @override
  Future<bool> handle(
    Uri uri, {
    required DeeplinkSource source,
    Map<String, dynamic>? payload,
  }) async {
    MagicRoute.to(uri.path, query: uri.queryParameters);
    return true;
  }
}
