import 'dart:async';

import 'package:magic/magic.dart';
import 'package:magic_deeplink/src/handlers/deeplink_handler.dart';

import '../events/deeplink_events.dart';
import 'tenant_switch_gate.dart';

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

  /// Switches the session's tenant before navigating, for a push whose payload
  /// names another one.
  ///
  /// `null` (the default) never switches anything. See [TenantSwitchGate] for
  /// the contract; the source and payload-key checks live in [handle] so no
  /// gate configuration can loosen them.
  final TenantSwitchGate? tenantGate;

  final List<RegExp> _patterns;

  /// The container key magic binds its log manager under.
  static const String _logBinding = 'log';

  RouteDeeplinkHandler({
    required this.paths,
    this.hosts,
    this.caseSensitive = false,
    this.tenantGate,
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

    return _matchedPattern(uri) != null;
  }

  /// The entry of [paths] whose pattern [uri]'s path matches, or null.
  ///
  /// What a breadcrumb reports instead of the path itself, since a concrete
  /// path can carry a token (`/invitations/:token/accept`).
  String? _matchedPattern(Uri uri) {
    String path = uri.path;

    // Normalize path: remove trailing slash unless it's just "/"
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    for (int i = 0; i < _patterns.length; i++) {
      if (_patterns[i].hasMatch(path)) return paths[i];
    }

    return null;
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

  /// Opens the path [uri] names, and answers whether it was opened.
  ///
  /// Never throws, per the handler contract: the manager awaits this from a
  /// stream subscription, so an escaping error (a router that is not built
  /// yet answers with a StateError) is an unhandled async error that takes a
  /// tapped notification with it. Every failure is logged and answered false.
  ///
  /// [source] and [payload] matter only to [tenantGate]: routing to a path the
  /// consumer listed is safe whoever asked for it, moving the session's tenant
  /// is not.
  @override
  Future<bool> handle(
    Uri uri, {
    required DeeplinkSource source,
    Map<String, dynamic>? payload,
  }) async {
    // The manager asks [canHandle] first, so this refuses only a direct call.
    // It still refuses rather than trusting its caller, because the guard is
    // the thing this class is for.
    if (!canHandle(uri)) {
      _log(
        Log.warning,
        'a link from ${source.name} names no path this handler serves: '
        '"${uri.path}"',
      );

      return false;
    }

    try {
      return await _open(uri, source: source, payload: payload);
    } catch (error) {
      // Not rethrown: see the contract above. Logged, because nothing retries.
      _log(Log.error, 'opening ${uri.path} failed: $error');

      return false;
    }
  }

  /// Navigates to [uri], switching tenant first when a push says the page
  /// belongs to one the session is not on.
  Future<bool> _open(
    Uri uri, {
    required DeeplinkSource source,
    required Map<String, dynamic>? payload,
  }) async {
    final TenantSwitchGate? gate = tenantGate;

    _announce(
      DeeplinkOpened(
        source: source,
        route: _matchedPattern(uri) ?? '',
        namesTenant: gate != null && gate.tenantNamedBy(payload).isNotEmpty,
      ),
    );

    // 1. Only a push may name the owner, and only through its payload. An OS
    //    link naming another tenant navigates anyway and meets the backend's
    //    404, which beats a link nobody authored moving the session.
    if (gate == null || source != DeeplinkSource.push) {
      _navigate(uri);

      return true;
    }

    // 2. An absent owner or an unresolved session is not evidence of a
    //    mismatch: a server older than the payload key must not leave a
    //    responder where they were.
    final String owner = gate.tenantNamedBy(payload);
    final String current = gate.currentTenantId()?.trim() ?? '';
    if (owner.isEmpty || current.isEmpty || owner == current) {
      _navigate(uri);

      return true;
    }

    // 3. A failed switch does not navigate: the backend still resolves the
    //    page against the old tenant, so going anyway lands on the same 404.
    final bool switched = await gate.switchTenant(owner);
    if (!switched) {
      gate.onSwitchFailed?.call(owner);
      _log(
        Log.error,
        'could not switch to tenant $owner; staying put rather than opening '
        '${uri.path} on a 404',
      );

      return false;
    }

    // 4. Say so before moving: the switch is otherwise silent, and the user
    //    would read another tenant's screens believing they are on their own.
    gate.onSwitched?.call();
    _navigate(uri);

    return true;
  }

  /// Hands the router the value [canHandle] validated, and no other.
  ///
  /// The parsed path rather than the string it came from: [Uri] resolves dot
  /// segments while parsing, and validating one value while navigating another
  /// is the shape every bypass of the path guard would take.
  void _navigate(Uri uri) {
    _announce(DeeplinkNavigating(route: _matchedPattern(uri) ?? ''));

    MagicRoute.to(uri.path, query: uri.queryParameters);
  }

  /// Dispatches [event] without waiting on its listeners.
  ///
  /// A breadcrumb may cost the navigation nothing: a listener that fails, or a
  /// dispatcher that cannot run, is logged and the link still opens.
  void _announce(MagicEvent event) {
    unawaited(
      Event.dispatch(event).catchError((Object error) {
        _log(Log.warning, 'dispatching ${event.runtimeType} failed: $error');
      }),
    );
  }

  /// Writes [message] through [write] when the host has a log to write to.
  ///
  /// [Log] throws when nothing bound `log`, and an app without a logging
  /// provider is a legitimate build; asking first keeps a diagnostic from
  /// becoming a second failure inside a handler that must not throw.
  void _log(void Function(String message) write, String message) {
    if (!Magic.bound(_logBinding)) return;

    write('[RouteDeeplinkHandler] $message');
  }
}
