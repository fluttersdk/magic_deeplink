import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_deeplink/fluttersdk_magic_deeplink.dart';

void main() {
  test('can import library and access all public exports', () {
    // Exceptions
    expect(DeeplinkException('msg'), isA<DeeplinkException>());

    // Managers
    expect(DeeplinkManager(), isA<DeeplinkManager>());

    // Contracts
    expect(DeeplinkHandler, isNotNull);
    expect(DeeplinkDriver, isNotNull);

    // Implementations
    expect(RouteDeeplinkHandler, isNotNull);
    expect(OneSignalDeeplinkHandler, isNotNull);

    // Providers
    expect(DeeplinkServiceProvider, isNotNull);
  });
}
