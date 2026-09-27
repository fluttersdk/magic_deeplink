import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_deeplink/src/events/deeplink_events.dart';
import 'package:magic_deeplink/src/handlers/deeplink_handler.dart';
import 'package:magic_deeplink/src/handlers/route_deeplink_handler.dart';
import 'package:magic_deeplink/src/handlers/tenant_switch_gate.dart';

void main() {
  group('DeeplinkOpened', () {
    test('reports source, route pattern and whether a tenant was named', () {
      final DeeplinkOpened event = DeeplinkOpened(
        source: DeeplinkSource.push,
        route: '/incidents/:id',
        namesTenant: true,
      );

      expect(event, isA<MagicEvent>());
      expect(event, isA<ReportsBreadcrumb>());
      expect(event.breadcrumbCategory, 'deeplink.open');
      expect(event.breadcrumbMessage, isNotEmpty);
      expect(event.breadcrumbData, <String, Object?>{
        'source': 'push',
        'route': '/incidents/:id',
        'names_tenant': true,
      });
    });
  });

  group('DeeplinkNavigating', () {
    test('reports the route pattern only', () {
      final DeeplinkNavigating event = DeeplinkNavigating(
        route: '/incidents/:id',
      );

      expect(event, isA<MagicEvent>());
      expect(event, isA<ReportsBreadcrumb>());
      expect(event.breadcrumbCategory, 'deeplink.navigate');
      expect(event.breadcrumbMessage, isNotEmpty);
      expect(event.breadcrumbData, <String, Object?>{
        'route': '/incidents/:id',
      });
    });
  });

  group('RouteDeeplinkHandler dispatches', () {
    /// Everything that happened, in order: dispatched events by type name,
    /// switches as `switch:<id>`, and the router path each event saw.
    late List<String> timeline;
    late List<MagicEvent> events;
    late void Function() stopListening;

    RouteDeeplinkHandler handlerWith({bool switchAnswer = true}) {
      return RouteDeeplinkHandler(
        paths: [
          '/',
          '/incidents/:id',
        ],
        tenantGate: TenantSwitchGate(
          currentTenantId: () => 'mine',
          switchTenant: (String tenantId) async {
            timeline.add('switch:$tenantId');

            return switchAnswer;
          },
        ),
      );
    }

    Future<void> mountRouter(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: MagicRouter.instance.routerConfig),
      );
      await tester.pumpAndSettle();
    }

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

      timeline = <String>[];
      events = <MagicEvent>[];
      stopListening = Event.listenAny((MagicEvent event) {
        if (event is! DeeplinkOpened && event is! DeeplinkNavigating) return;

        events.add(event);
        timeline.add(
          '${event.runtimeType}@${MagicRouter.instance.currentPath}',
        );
      });
    });

    tearDown(() {
      stopListening();
      MagicRouter.reset();
      MagicApp.reset();
      Magic.flush();
    });

    testWidgets('opened before the switch, navigating before the navigation', (
      WidgetTester tester,
    ) async {
      await mountRouter(tester);

      await open(
        tester,
        handlerWith(),
        '/incidents/1',
        source: DeeplinkSource.push,
        payload: <String, dynamic>{'team_id': 'other'},
      );

      expect(timeline, <String>[
        'DeeplinkOpened@/',
        'switch:other',
        'DeeplinkNavigating@/',
      ]);
      expect(MagicRouter.instance.currentPath, '/incidents/1');
      expect((events.first as DeeplinkOpened).namesTenant, isTrue);
    });

    testWidgets('a failed switch dispatches no navigating event', (
      WidgetTester tester,
    ) async {
      await mountRouter(tester);

      await open(
        tester,
        handlerWith(switchAnswer: false),
        '/incidents/1',
        source: DeeplinkSource.push,
        payload: <String, dynamic>{'team_id': 'other'},
      );

      expect(events.map((MagicEvent e) => e.runtimeType), <Type>[
        DeeplinkOpened,
      ]);
    });

    testWidgets('events carry no query string and no payload value', (
      WidgetTester tester,
    ) async {
      await mountRouter(tester);

      await open(
        tester,
        handlerWith(),
        '/incidents/1?token=s3cret-query',
        source: DeeplinkSource.push,
        payload: <String, dynamic>{
          'team_id': 'tenant-value',
          'token': 's3cret-payload',
        },
      );

      expect(events, hasLength(2));
      for (final MagicEvent event in events) {
        final ReportsBreadcrumb crumb = event as ReportsBreadcrumb;
        final String data = crumb.breadcrumbData.values
            .map((Object? value) => '$value')
            .join(' ');

        expect(data, isNot(contains('?')));
        expect(data, isNot(contains('s3cret')));
        expect(data, isNot(contains('tenant-value')));
        expect(crumb.breadcrumbMessage, isNot(contains('s3cret')));
      }
    });

    test(
        'a token in the path never reaches a breadcrumb: the route pattern does',
        () async {
      final RouteDeeplinkHandler handler = RouteDeeplinkHandler(
        paths: ['/invitations/:token/accept'],
      );

      await handler.handle(
        Uri.parse('/invitations/s3cret-invite/accept'),
        source: DeeplinkSource.osLink,
      );

      final String data = events
          .map((MagicEvent e) => (e as ReportsBreadcrumb).breadcrumbData.values)
          .expand((Iterable<Object?> values) => values)
          .join(' ');

      expect(data, isNot(contains('s3cret-invite')));
      expect(
        (events.first as ReportsBreadcrumb).breadcrumbData['route'],
        '/invitations/:token/accept',
      );
    });

    test('a handler without a gate reports that no tenant was named', () async {
      final RouteDeeplinkHandler handler = RouteDeeplinkHandler(
        paths: ['/incidents/:id'],
      );

      await handler.handle(
        Uri.parse('/incidents/1'),
        source: DeeplinkSource.push,
        payload: <String, dynamic>{'team_id': 'other'},
      );

      expect((events.first as DeeplinkOpened).namesTenant, isFalse);
    });
  });
}
