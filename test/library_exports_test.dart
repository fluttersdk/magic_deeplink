import 'package:flutter_test/flutter_test.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

void main() {
  test('can import library and access all public exports', () {
    // Exceptions
    expect(DeeplinkException('msg'), isA<DeeplinkException>());

    // Managers
    expect(DeeplinkManager(), isA<DeeplinkManager>());

    // Contracts
    expect(DeeplinkHandler, isNotNull);
    expect(DeeplinkDriver, isNotNull);
    expect(
      DeeplinkSource.values,
      [DeeplinkSource.osLink, DeeplinkSource.push, DeeplinkSource.manual],
    );

    // Implementations
    expect(RouteDeeplinkHandler, isNotNull);
    expect(OneSignalDeeplinkHandler, isNotNull);

    // Providers
    expect(DeeplinkServiceProvider, isNotNull);
  });
}
