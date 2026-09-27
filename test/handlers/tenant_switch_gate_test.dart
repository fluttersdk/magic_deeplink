import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_deeplink/src/handlers/deeplink_handler.dart';
import 'package:magic_deeplink/src/handlers/route_deeplink_handler.dart';
import 'package:magic_deeplink/src/handlers/tenant_switch_gate.dart';

void main() {
  /// Every tenant id handed to `switchTenant`, in call order.
  late List<String> switchedTo;

  /// Every tenant id handed to `onSwitchFailed`, in call order.
  late List<String> failedFor;

  /// The router's path at the moment `onSwitched` ran, or null when it never
  /// ran. Captured so "switched, THEN navigated" is an assertion rather than an
  /// assumption.
  String? pathWhenSwitched;
  late bool onSwitchedCalled;

  /// A gate whose session sits on [current] and whose switch answers
  /// [switchAnswer].
  TenantSwitchGate gate({
    String? current = 'mine',
    bool switchAnswer = true,
    String payloadKey = 'team_id',
  }) {
    return TenantSwitchGate(
      payloadKey: payloadKey,
      currentTenantId: () => current,
      switchTenant: (String tenantId) async {
        switchedTo.add(tenantId);

        return switchAnswer;
      },
      onSwitched: () {
        onSwitchedCalled = true;
        pathWhenSwitched = MagicRouter.instance.currentPath;
      },
      onSwitchFailed: failedFor.add,
    );
  }

  RouteDeeplinkHandler handlerWith(TenantSwitchGate? tenantGate) {
    return RouteDeeplinkHandler(
      paths: [
        '/',
        '/incidents/:id',
        '/monitors/:id',
      ],
      tenantGate: tenantGate,
    );
  }

  /// Mounts the router so a navigation has somewhere to land.
  Future<void> mountRouter(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: MagicRouter.instance.routerConfig),
    );
    await tester.pumpAndSettle();
  }

  /// Hands [uri] to [handler] and pumps until the switch and the navigation
  /// have both settled. The future is held rather than awaited first, because
  /// nothing pumps frames behind a bare await inside the tester's zone.
  Future<bool> open(
    WidgetTester tester,
    RouteDeeplinkHandler handler,
    String uri, {
    required DeeplinkSource source,
    Map<String, dynamic>? payload,
  }) async {
    final Future<bool> handled = handler.handle(
      Uri.parse(uri),
      source: source,
      payload: payload,
    );

    await tester.pumpAndSettle();

    return handled;
  }

  setUp(() {
    MagicApp.reset();
    Magic.flush();
    // The router reads the auth state to re-run redirects; faked so it has one.
    Auth.fake();
    MagicRouter.reset();
    MagicRoute.page('/', () => const SizedBox());
    MagicRoute.page('/incidents/:id', () => const SizedBox());
    MagicRoute.page('/monitors/:id', () => const SizedBox());

    switchedTo = <String>[];
    failedFor = <String>[];
    pathWhenSwitched = null;
    onSwitchedCalled = false;
  });

  tearDown(() {
    MagicRouter.reset();
    MagicApp.reset();
    Magic.flush();
  });

  group('a push naming another tenant', () {
    testWidgets('switches once, calls onSwitched, then navigates', (
      WidgetTester tester,
    ) async {
      await mountRouter(tester);

      final bool handled = await open(
        tester,
        handlerWith(gate()),
        '/incidents/1',
        source: DeeplinkSource.push,
        payload: <String, dynamic>{'team_id': 'other'},
      );

      expect(handled, isTrue);
      expect(switchedTo, <String>['other']);
      expect(onSwitchedCalled, isTrue);
      expect(pathWhenSwitched, '/');
      expect(MagicRouter.instance.currentPath, '/incidents/1');
      expect(failedFor, isEmpty);
    });

    testWidgets('a failed switch reports and does not navigate', (
      WidgetTester tester,
    ) async {
      await mountRouter(tester);

      final bool handled = await open(
        tester,
        handlerWith(gate(switchAnswer: false)),
        '/incidents/1',
        source: DeeplinkSource.push,
        payload: <String, dynamic>{'team_id': 'other'},
      );

      expect(handled, isFalse);
      expect(switchedTo, <String>['other']);
      expect(failedFor, <String>['other']);
      expect(onSwitchedCalled, isFalse);
      expect(MagicRouter.instance.currentPath, '/');
    });

    testWidgets('a switch that throws answers false and does not navigate', (
      WidgetTester tester,
    ) async {
      await mountRouter(tester);

      final RouteDeeplinkHandler handler = handlerWith(
        TenantSwitchGate(
          currentTenantId: () => 'mine',
          switchTenant: (String tenantId) async => throw StateError('offline'),
          onSwitchFailed: failedFor.add,
        ),
      );

      final bool handled = await open(
        tester,
        handler,
        '/incidents/1',
        source: DeeplinkSource.push,
        payload: <String, dynamic>{'team_id': 'other'},
      );

      expect(handled, isFalse);
      expect(failedFor, <String>['other']);
      expect(MagicRouter.instance.currentPath, '/');
    });

    testWidgets('an onSwitched that throws still opens the link', (
      WidgetTester tester,
    ) async {
      await mountRouter(tester);

      final RouteDeeplinkHandler handler = handlerWith(
        TenantSwitchGate(
          currentTenantId: () => 'mine',
          switchTenant: (String tenantId) async => true,
          onSwitched: () => throw StateError('no overlay'),
        ),
      );

      final bool handled = await open(
        tester,
        handler,
        '/incidents/1',
        source: DeeplinkSource.push,
        payload: <String, dynamic>{'team_id': 'other'},
      );

      expect(handled, isTrue);
      expect(MagicRouter.instance.currentPath, '/incidents/1');
    });

    testWidgets('reads the tenant from a custom payload key', (
      WidgetTester tester,
    ) async {
      await mountRouter(tester);

      await open(
        tester,
        handlerWith(gate(payloadKey: 'workspace')),
        '/incidents/1',
        source: DeeplinkSource.push,
        payload: <String, dynamic>{
          'team_id': 'ignored',
          'workspace': 'other',
        },
      );

      expect(switchedTo, <String>['other']);
    });
  });

  group('only a push may switch', () {
    testWidgets('an OS link never switches', (WidgetTester tester) async {
      // The tenant key sits in BOTH places an attacker could try: the payload
      // and the query. Neither may move the session, and the link still opens.
      await mountRouter(tester);

      final bool handled = await open(
        tester,
        handlerWith(gate()),
        '/incidents/1?team_id=other',
        source: DeeplinkSource.osLink,
        payload: <String, dynamic>{'team_id': 'other'},
      );

      expect(handled, isTrue);
      expect(switchedTo, isEmpty);
      expect(MagicRouter.instance.currentPath, '/incidents/1');
    });

    testWidgets('a manual link never switches', (WidgetTester tester) async {
      await mountRouter(tester);

      await open(
        tester,
        handlerWith(gate()),
        '/incidents/1',
        source: DeeplinkSource.manual,
        payload: <String, dynamic>{'team_id': 'other'},
      );

      expect(switchedTo, isEmpty);
      expect(MagicRouter.instance.currentPath, '/incidents/1');
    });

    testWidgets('a push naming the tenant only in its query never switches', (
      WidgetTester tester,
    ) async {
      await mountRouter(tester);

      final bool handled = await open(
        tester,
        handlerWith(gate()),
        '/incidents/1?team_id=other',
        source: DeeplinkSource.push,
        payload: <String, dynamic>{'deep_link': '/incidents/1?team_id=other'},
      );

      expect(handled, isTrue);
      expect(switchedTo, isEmpty);
      expect(MagicRouter.instance.currentPath, '/incidents/1');
    });
  });

  group('no mismatch, no switch', () {
    testWidgets('an int id on the wire equals the same id as a string', (
      WidgetTester tester,
    ) async {
      await mountRouter(tester);

      final bool handled = await open(
        tester,
        handlerWith(gate(current: 5.toString())),
        '/incidents/1',
        source: DeeplinkSource.push,
        payload: <String, dynamic>{'team_id': 5},
      );

      expect(handled, isTrue);
      expect(switchedTo, isEmpty);
      expect(MagicRouter.instance.currentPath, '/incidents/1');
    });

    testWidgets('ids are compared trimmed', (WidgetTester tester) async {
      await mountRouter(tester);

      await open(
        tester,
        handlerWith(gate(current: '5')),
        '/incidents/1',
        source: DeeplinkSource.push,
        payload: <String, dynamic>{'team_id': ' 5 '},
      );

      expect(switchedTo, isEmpty);
      expect(MagicRouter.instance.currentPath, '/incidents/1');
    });

    testWidgets('a payload naming no tenant navigates without switching', (
      WidgetTester tester,
    ) async {
      await mountRouter(tester);

      await open(
        tester,
        handlerWith(gate()),
        '/incidents/1',
        source: DeeplinkSource.push,
        payload: <String, dynamic>{'team_id': '   '},
      );

      expect(switchedTo, isEmpty);
      expect(MagicRouter.instance.currentPath, '/incidents/1');
    });

    testWidgets('an unresolved current tenant navigates without switching', (
      WidgetTester tester,
    ) async {
      await mountRouter(tester);

      await open(
        tester,
        handlerWith(gate(current: null)),
        '/incidents/1',
        source: DeeplinkSource.push,
        payload: <String, dynamic>{'team_id': 'other'},
      );

      expect(switchedTo, isEmpty);
      expect(MagicRouter.instance.currentPath, '/incidents/1');
    });
  });

  group('navigation', () {
    testWidgets('forwards the query of the parsed link', (
      WidgetTester tester,
    ) async {
      await mountRouter(tester);

      await open(
        tester,
        handlerWith(gate()),
        '/monitors/m-1?tab=checks',
        source: DeeplinkSource.push,
        payload: null,
      );

      expect(MagicRouter.instance.currentLocation, '/monitors/m-1?tab=checks');
    });

    testWidgets('a link the handler does not claim is refused, not opened', (
      WidgetTester tester,
    ) async {
      await mountRouter(tester);

      final bool handled = await open(
        tester,
        handlerWith(gate()),
        '/unknown/1',
        source: DeeplinkSource.push,
        payload: <String, dynamic>{'team_id': 'other'},
      );

      expect(handled, isFalse);
      expect(switchedTo, isEmpty);
      expect(MagicRouter.instance.currentPath, '/');
    });

    test('handle never throws when the router is not built', () async {
      final bool handled = await handlerWith(null).handle(
        Uri.parse('/incidents/1'),
        source: DeeplinkSource.osLink,
      );

      expect(handled, isFalse);
    });
  });
}
