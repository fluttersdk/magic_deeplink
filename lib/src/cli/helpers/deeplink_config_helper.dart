/// Helper class for generating deep link configuration templates.
class DeeplinkConfigHelper {
  /// Returns a standardized Dart configuration template for deep links.
  ///
  /// The template includes default values for driver, domain, scheme, and platform-specific
  /// configuration for iOS and Android.
  static String getDeeplinkConfigTemplate() {
    return r'''Map<String, dynamic> get deeplinkConfig => {
  'deeplink': {
    'enabled': true,
    'driver': 'app_links',
    'domain': 'example.com',
    'scheme': 'https',

    'ios': {
      'team_id': 'YOUR_TEAM_ID',
      'bundle_id': 'com.example.app',
    },

    'android': {
      'package_name': 'com.example.app',
      'sha256_fingerprints': [
        'YOUR_SHA256_FINGERPRINT',
      ],
    },

    'paths': [
      '/*',
    ],
  },
};''';
  }
}
