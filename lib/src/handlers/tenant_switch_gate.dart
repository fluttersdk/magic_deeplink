import 'package:flutter/foundation.dart';

/// Lets a tapped push move the session onto the tenant (team, workspace,
/// organisation) that owns the page it opens, before `RouteDeeplinkHandler`
/// navigates there.
///
/// A multi-tenant backend resolves a page against the session's CURRENT
/// tenant and answers 404 for another tenant's row, so a push paging a
/// responder about another team's incident would land on that 404. The gate
/// switches first instead.
///
/// The security contract lives in the handler and is not configurable:
///
/// - Only a `DeeplinkSource.push` may switch. Its payload was authored by the
///   server; an OS link is whatever the device was asked to open, and anyone
///   who can send the device a link can craft one.
/// - The tenant is read from the payload under [payloadKey] and never from the
///   URI query, because the query is part of the link.
/// - Ids compare as trimmed strings, so a wire `5` and a local `'5'` are the
///   same tenant.
/// - A switch that answers false, or throws, does not navigate: the backend
///   would still resolve the page against the old tenant.
@immutable
class TenantSwitchGate {
  /// The push payload key naming the tenant that owns what the link opens.
  final String payloadKey;

  /// The session's current tenant id, or null while it has not resolved. A
  /// null answer navigates without switching: an unresolved session is not
  /// evidence of a mismatch.
  final String? Function() currentTenantId;

  /// Moves the session onto [tenantId] and answers whether it took.
  final Future<bool> Function(String tenantId) switchTenant;

  /// Runs after a successful switch and before the navigation, so the app can
  /// tell the user their tenant changed under them. One that throws is logged
  /// and the link still opens: the session has already moved.
  final void Function()? onSwitched;

  /// Runs when [switchTenant] answered false or threw, with the tenant it was
  /// asked for. The link is not opened after this.
  final void Function(String tenantId)? onSwitchFailed;

  const TenantSwitchGate({
    required this.currentTenantId,
    required this.switchTenant,
    this.payloadKey = 'team_id',
    this.onSwitched,
    this.onSwitchFailed,
  });

  /// The tenant [payload] names under [payloadKey], trimmed, or an empty
  /// string when it names none.
  String tenantNamedBy(Map<String, dynamic>? payload) {
    return payload?[payloadKey]?.toString().trim() ?? '';
  }
}
