import 'dart:convert';
import 'dart:io';

// Import artisan without DoctorCommand to avoid collision with the
// deeplink-specific DoctorCommand below.
import 'package:fluttersdk_artisan/artisan.dart' hide DoctorCommand;
import 'package:magic_deeplink/src/cli/commands/doctor_command.dart';
import 'package:test/test.dart';

/// Test double that overrides [getProjectRoot] to use a temp directory.
class _TestDoctorCommand extends DoctorCommand {
  final String _root;

  _TestDoctorCommand(this._root);

  @override
  String getProjectRoot() => _root;
}

/// Test double that fails the test if a remote fetch is ever attempted,
/// used to prove the default run makes no network call.
class _NoNetworkDoctorCommand extends _TestDoctorCommand {
  _NoNetworkDoctorCommand(super.root);

  @override
  Future<RemoteAssociationFile> fetchRemoteFile(Uri uri) {
    fail('fetchRemoteFile must not be called without --remote');
  }
}

/// Test double that returns a canned [RemoteAssociationFile] per URI,
/// avoiding any real network access.
class _FakeRemoteDoctorCommand extends _TestDoctorCommand {
  _FakeRemoteDoctorCommand(super.root, this._responses);

  final Map<String, RemoteAssociationFile> _responses;

  @override
  Future<RemoteAssociationFile> fetchRemoteFile(Uri uri) async {
    final response = _responses[uri.toString()];
    if (response == null) {
      throw StateError('No fake response registered for $uri');
    }
    return response;
  }
}

/// Writes a fully valid deeplink config to the temp project.
void _writeValidConfig(
  Directory tempDir, {
  String domain = 'app.example.com',
  String teamId = 'ABCDE12345',
  String bundleId = 'com.example.myapp',
  String packageName = 'com.example.myapp',
  List<String> fingerprints = const [
    'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77',
  ],
}) {
  Directory('${tempDir.path}/lib/config').createSync(recursive: true);
  final fingerprintLiterals =
      fingerprints.map((f) => "'$f'").join(',\n        ');
  File('${tempDir.path}/lib/config/deeplink.dart').writeAsStringSync('''
Map<String, dynamic> get deeplinkConfig => {
  'deeplink': {
    'domain': '$domain',
    'ios': {
      'team_id': '$teamId',
      'bundle_id': '$bundleId',
    },
    'android': {
      'package_name': '$packageName',
      'sha256_fingerprints': [
        $fingerprintLiterals,
      ],
    },
    'paths': ['/*'],
  },
};
''');
}

/// Writes a valid iOS project: `Info.plist` with `FlutterDeepLinkingEnabled`
/// false, `Runner.entitlements` with an `applinks:` host matching [domain].
///
/// Each of the two markers is independently switchable so a test can drop
/// one at a time.
void _writeIosProject(
  Directory tempDir, {
  String domain = 'app.example.com',
  bool deepLinkingDisabled = true,
  bool includeEntitlements = true,
  String? entitlementsHost,
}) {
  Directory('${tempDir.path}/ios/Runner').createSync(recursive: true);

  final deepLinkingBlock = deepLinkingDisabled
      ? '<key>FlutterDeepLinkingEnabled</key>\n\t<false/>\n'
      : '';

  File('${tempDir.path}/ios/Runner/Info.plist').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>test_app</string>
	$deepLinkingBlock</dict>
</plist>
''');

  if (includeEntitlements) {
    final host = entitlementsHost ?? domain;
    File('${tempDir.path}/ios/Runner/Runner.entitlements').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.associated-domains</key>
	<array>
		<string>applinks:$host</string>
	</array>
</dict>
</plist>
''');
  }
}

/// Writes a valid Android manifest: `flutter_deeplinking_enabled` correctly
/// placed inside `<activity>`, and an autoVerify intent-filter carrying both
/// `http`/`https` schemes and a host matching [domain].
///
/// [deepLinkingInApplication] moves the meta-data to the `<application>`
/// element instead — the failure mode the command exists to catch.
void _writeAndroidManifest(
  Directory tempDir, {
  String domain = 'app.example.com',
  bool deepLinkingInApplication = false,
  bool includeAutoVerifyFilter = true,
  bool includeHttpScheme = true,
  bool includeHttpsScheme = true,
  String? host,
}) {
  Directory('${tempDir.path}/android/app/src/main').createSync(recursive: true);

  final deepLinkingMetaData = '''
            <meta-data
                android:name="flutter_deeplinking_enabled"
                android:value="false"/>
''';

  final autoVerifyFilter = includeAutoVerifyFilter
      ? '''
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                ${includeHttpScheme ? '<data android:scheme="http"/>' : ''}
                ${includeHttpsScheme ? '<data android:scheme="https"/>' : ''}
                <data android:host="${host ?? domain}"/>
            </intent-filter>
'''
      : '';

  File('${tempDir.path}/android/app/src/main/AndroidManifest.xml')
      .writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="test_app" android:name="\${applicationName}">
        ${deepLinkingInApplication ? deepLinkingMetaData : ''}
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            ${deepLinkingInApplication ? '' : deepLinkingMetaData}
            $autoVerifyFilter
        </activity>
    </application>
</manifest>
''');
}

/// Writes valid `apple-app-site-association` and `assetlinks.json` files
/// under `web/.well-known/` matching the given identity.
void _writeAssociationFiles(
  Directory tempDir, {
  String teamId = 'ABCDE12345',
  String bundleId = 'com.example.myapp',
  String packageName = 'com.example.myapp',
  List<String> fingerprints = const [
    'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77',
  ],
  bool mixLegacyFormat = false,
}) {
  Directory('${tempDir.path}/web/.well-known').createSync(recursive: true);

  final details = <Map<String, dynamic>>[
    {
      'appIDs': ['$teamId.$bundleId'],
      'components': [
        {'/': '/*', 'comment': 'Matches any URL whose path matches /*'},
      ],
    },
  ];
  if (mixLegacyFormat) {
    details.add({
      'appID': '$teamId.$bundleId',
      'paths': ['/*'],
    });
  }

  File('${tempDir.path}/web/.well-known/apple-app-site-association')
      .writeAsStringSync(jsonEncode({
    'applinks': {'details': details},
  }));

  File('${tempDir.path}/web/.well-known/assetlinks.json').writeAsStringSync(
    jsonEncode([
      {
        'relation': ['delegate_permission/common.handle_all_urls'],
        'target': {
          'namespace': 'android_app',
          'package_name': packageName,
          'sha256_cert_fingerprints': fingerprints,
        },
      },
    ]),
  );
}

/// Assembles a fully valid project (config + iOS + Android + associations)
/// under [tempDir] using a shared identity across every file.
void _writeFullyConfiguredProject(Directory tempDir) {
  _writeValidConfig(tempDir);
  _writeIosProject(tempDir);
  _writeAndroidManifest(tempDir);
  _writeAssociationFiles(tempDir);
}

void main() {
  late Directory tempDir;
  late _TestDoctorCommand command;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('deeplink_doctor_test_');
    command = _TestDoctorCommand(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DoctorCommand metadata', () {
    test('name is "deeplink:doctor"', () {
      expect(command.name, equals('deeplink:doctor'));
    });

    test('description is not empty', () {
      expect(command.description, isNotEmpty);
    });
  });

  group('a fully configured project', () {
    test('has no missing requirements', () {
      _writeFullyConfiguredProject(tempDir);
      expect(command.getMissingRequirements(), isEmpty);
    });

    test('has no warnings', () {
      _writeFullyConfiguredProject(tempDir);
      expect(command.getWarnings(), isEmpty);
    });

    test('exits 0 and reports all checks passed', () async {
      _writeFullyConfiguredProject(tempDir);
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(
          {'verbose': false, 'remote': false},
          signature: command.parsedSignature,
        ),
        output,
      );
      expect(await command.handle(ctx), 0);
      expect(output.content, contains('All checks passed'));
    });
  });

  // ---------------------------------------------------------------------------
  // 1 + 2: config existence, parseability, placeholders
  // ---------------------------------------------------------------------------

  group('validateConfig', () {
    test('returns no issues for a fully valid config', () {
      _writeValidConfig(tempDir);
      expect(command.validateConfig(), isEmpty);
    });

    test('reports config file missing', () {
      final issues = command.validateConfig();
      expect(issues.single, contains('not found'));
    });

    test('reports a scaffold placeholder domain', () {
      _writeValidConfig(tempDir, domain: 'example.com');
      expect(
        command.validateConfig().any((i) => i.contains('example.com')),
        isTrue,
      );
    });

    test('reports a scaffold placeholder team_id', () {
      _writeValidConfig(tempDir, teamId: 'YOUR_TEAM_ID');
      expect(
        command.validateConfig().any((i) => i.contains('YOUR_TEAM_ID')),
        isTrue,
      );
    });

    test('reports a scaffold placeholder bundle_id', () {
      _writeValidConfig(tempDir, bundleId: 'com.example.app');
      expect(
        command.validateConfig().any(
            (i) => i.contains('bundle_id') && i.contains('com.example.app')),
        isTrue,
      );
    });

    test('reports a scaffold placeholder package_name', () {
      _writeValidConfig(tempDir, packageName: 'com.example.app');
      expect(
        command.validateConfig().any(
            (i) => i.contains('package_name') && i.contains('com.example.app')),
        isTrue,
      );
    });

    test('reports a scaffold placeholder fingerprint', () {
      _writeValidConfig(tempDir,
          fingerprints: const ['YOUR_SHA256_FINGERPRINT']);
      expect(
        command
            .validateConfig()
            .any((i) => i.contains('YOUR_SHA256_FINGERPRINT')),
        isTrue,
      );
    });

    test('reports a missing domain key', () {
      Directory('${tempDir.path}/lib/config').createSync(recursive: true);
      File('${tempDir.path}/lib/config/deeplink.dart').writeAsStringSync('''
Map<String, dynamic> get deeplinkConfig => {
  'deeplink': {
    'ios': {'team_id': 'ABCDE12345', 'bundle_id': 'com.example.myapp'},
    'android': {
      'package_name': 'com.example.myapp',
      'sha256_fingerprints': ['AA:BB'],
    },
  },
};
''');
      expect(
        command.validateConfig().any((i) => i.contains('domain')),
        isTrue,
      );
    });

    test('tolerates a Dart generic annotation on the fingerprints list', () {
      Directory('${tempDir.path}/lib/config').createSync(recursive: true);
      File('${tempDir.path}/lib/config/deeplink.dart').writeAsStringSync('''
Map<String, dynamic> get deeplinkConfig => {
  'deeplink': {
    'domain': 'app.example.com',
    'ios': {'team_id': 'ABCDE12345', 'bundle_id': 'com.example.myapp'},
    'android': {
      'package_name': 'com.example.myapp',
      'sha256_fingerprints': <String>[
        'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77',
      ],
    },
    'paths': ['/*'],
  },
};
''');
      expect(command.validateConfig(), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // 3 + 4: iOS setup
  // ---------------------------------------------------------------------------

  group('iOS setup', () {
    List<String> iosIssues() => command
        .getMissingRequirements()
        .where((issue) => issue.startsWith('[ios]'))
        .toList();

    test('a correctly configured iOS project has no issues', () {
      _writeValidConfig(tempDir);
      _writeIosProject(tempDir);
      expect(iosIssues(), isEmpty);
    });

    test('reports Info.plist absent', () {
      Directory('${tempDir.path}/ios').createSync(recursive: true);
      _writeValidConfig(tempDir);
      final status =
          command.checkPlatformSetup()['ios'] as Map<String, dynamic>;
      expect(status['exists'], isFalse);
      expect(status['configured'], isFalse);
    });

    test('reports FlutterDeepLinkingEnabled missing', () {
      _writeValidConfig(tempDir);
      _writeIosProject(tempDir, deepLinkingDisabled: false);
      expect(
        iosIssues().any((i) => i.contains('FlutterDeepLinkingEnabled')),
        isTrue,
      );
    });

    test(
        'reports an associated-domains host that disagrees with deeplink.domain',
        () {
      _writeValidConfig(tempDir, domain: 'app.example.com');
      _writeIosProject(tempDir,
          domain: 'app.example.com', entitlementsHost: 'wrong-host.com');
      final issues = iosIssues();
      expect(issues.any((i) => i.contains('wrong-host.com')), isTrue);
      expect(issues.any((i) => i.contains('app.example.com')), isTrue);
    });

    test('reports the entitlements file missing', () {
      _writeValidConfig(tempDir);
      _writeIosProject(tempDir, includeEntitlements: false);
      expect(
        iosIssues().any((i) => i.toLowerCase().contains('entitlements')),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 5 + 6: Android setup — this is THE case the command exists for
  // ---------------------------------------------------------------------------

  group('Android setup', () {
    List<String> androidIssues() => command
        .getMissingRequirements()
        .where((issue) => issue.startsWith('[android]'))
        .toList();

    test('a correctly configured Android project has no issues', () {
      _writeValidConfig(tempDir);
      _writeAndroidManifest(tempDir);
      expect(androidIssues(), isEmpty);
    });

    test('reports AndroidManifest.xml absent', () {
      Directory('${tempDir.path}/android').createSync(recursive: true);
      _writeValidConfig(tempDir);
      final status =
          command.checkPlatformSetup()['android'] as Map<String, dynamic>;
      expect(status['exists'], isFalse);
      expect(status['configured'], isFalse);
    });

    test(
      'flags flutter_deeplinking_enabled placed in <application> instead of <activity> — '
      'a grep for the tag name cannot see this, only tree position can',
      () {
        _writeValidConfig(tempDir);
        _writeAndroidManifest(tempDir, deepLinkingInApplication: true);
        final issues = androidIssues();
        expect(
          issues.any((i) =>
              i.contains('flutter_deeplinking_enabled') &&
              i.contains('<application>')),
          isTrue,
        );
      },
    );

    test('reports flutter_deeplinking_enabled missing entirely', () {
      Directory('${tempDir.path}/android/app/src/main')
          .createSync(recursive: true);
      _writeValidConfig(tempDir);
      File('${tempDir.path}/android/app/src/main/AndroidManifest.xml')
          .writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="test_app">
        <activity android:name=".MainActivity">
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="http"/>
                <data android:scheme="https"/>
                <data android:host="app.example.com"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
''');
      expect(
        androidIssues().any((i) => i.contains('flutter_deeplinking_enabled')),
        isTrue,
      );
    });

    test('reports a missing autoVerify intent-filter', () {
      _writeValidConfig(tempDir);
      _writeAndroidManifest(tempDir, includeAutoVerifyFilter: false);
      expect(
        androidIssues().any((i) => i.contains('autoVerify')),
        isTrue,
      );
    });

    test('reports an intent-filter missing the http scheme', () {
      _writeValidConfig(tempDir);
      _writeAndroidManifest(tempDir, includeHttpScheme: false);
      expect(
        androidIssues().any((i) => i.toLowerCase().contains('http')),
        isTrue,
      );
    });

    test('reports an intent-filter missing the https scheme', () {
      _writeValidConfig(tempDir);
      _writeAndroidManifest(tempDir, includeHttpsScheme: false);
      expect(
        androidIssues().any((i) => i.toLowerCase().contains('https')),
        isTrue,
      );
    });

    test('reports an intent-filter host that disagrees with deeplink.domain',
        () {
      _writeValidConfig(tempDir, domain: 'app.example.com');
      _writeAndroidManifest(tempDir,
          domain: 'app.example.com', host: 'wrong-host.com');
      final issues = androidIssues();
      expect(issues.any((i) => i.contains('wrong-host.com')), isTrue);
      expect(issues.any((i) => i.contains('app.example.com')), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // 7: association files
  // ---------------------------------------------------------------------------

  group('association files', () {
    List<String> associationIssues() => command
        .getMissingRequirements()
        .where((issue) => issue.startsWith('[associations]'))
        .toList();

    test('correctly matching association files have no issues', () {
      _writeValidConfig(tempDir);
      _writeAssociationFiles(tempDir);
      expect(associationIssues(), isEmpty);
    });

    test('reports apple-app-site-association missing', () {
      _writeValidConfig(tempDir);
      Directory('${tempDir.path}/web/.well-known').createSync(recursive: true);
      File('${tempDir.path}/web/.well-known/assetlinks.json')
          .writeAsStringSync('[]');
      expect(
        associationIssues()
            .any((i) => i.contains('apple-app-site-association')),
        isTrue,
      );
    });

    test('reports assetlinks.json missing', () {
      _writeValidConfig(tempDir);
      Directory('${tempDir.path}/web/.well-known').createSync(recursive: true);
      File('${tempDir.path}/web/.well-known/apple-app-site-association')
          .writeAsStringSync('{}');
      expect(
        associationIssues().any((i) => i.contains('assetlinks.json')),
        isTrue,
      );
    });

    test(
      'reports an AASA appID that disagrees with team_id + bundle_id',
      () {
        _writeValidConfig(tempDir,
            teamId: 'ABCDE12345', bundleId: 'com.example.myapp');
        _writeAssociationFiles(tempDir,
            teamId: 'WRONGTEAM', bundleId: 'com.wrong.bundle');
        expect(
          associationIssues()
              .any((i) => i.contains('ABCDE12345.com.example.myapp')),
          isTrue,
        );
      },
    );

    test('reports assetlinks.json package_name mismatch', () {
      _writeValidConfig(tempDir, packageName: 'com.example.myapp');
      _writeAssociationFiles(tempDir, packageName: 'com.wrong.package');
      expect(
        associationIssues().any((i) => i.contains('com.example.myapp')),
        isTrue,
      );
    });

    test('reports assetlinks.json fingerprint mismatch', () {
      _writeValidConfig(
        tempDir,
        fingerprints: const ['AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA'],
      );
      _writeAssociationFiles(
        tempDir,
        fingerprints: const ['BB:BB:BB:BB:BB:BB:BB:BB:BB:BB:BB:BB:BB:BB:BB:BB'],
      );
      expect(
        associationIssues().any((i) => i.contains('AA:AA:AA')),
        isTrue,
      );
    });

    test('warns, but does not fail, on mixed legacy + modern AASA formats', () {
      _writeValidConfig(tempDir);
      _writeAssociationFiles(tempDir, mixLegacyFormat: true);

      expect(associationIssues(), isEmpty);
      expect(
        command.getWarnings().any((w) => w.toLowerCase().contains('legacy')),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Report + exit codes
  // ---------------------------------------------------------------------------

  group('generateReport', () {
    test('shows a failing check with a cross', () {
      final report = command.generateReport();
      expect(report, contains('✗'));
    });

    test('shows every passing check with a tick for a fully configured project',
        () {
      _writeFullyConfiguredProject(tempDir);
      expect(command.generateReport(), contains('All requirements met'));
    });

    test('names the one thing no local check can prove', () {
      final report = command.generateReport();
      expect(report.toLowerCase(), contains('device'));
    });

    test('verbose produces a longer report than the default', () {
      _writeFullyConfiguredProject(tempDir);
      final verbose = command.generateReport(verbose: true);
      final normal = command.generateReport(verbose: false);
      expect(verbose.length, greaterThan(normal.length));
    });
  });

  group('exit codes via handle()', () {
    test('a broken project exits 1', () async {
      final ctx = ArtisanContext.bare(
        MapInput(
          {'verbose': false, 'remote': false},
          signature: command.parsedSignature,
        ),
        BufferedOutput(),
      );
      expect(await command.handle(ctx), 1);
    });

    test('a warning-only project exits 0', () async {
      _writeValidConfig(tempDir);
      _writeAssociationFiles(tempDir, mixLegacyFormat: true);
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(
          {'verbose': false, 'remote': false},
          signature: command.parsedSignature,
        ),
        output,
      );
      expect(await command.handle(ctx), 0);
      expect(output.content, isNot(contains('All checks passed')));
    });
  });

  // ---------------------------------------------------------------------------
  // --remote (opt-in only, no network by default)
  // ---------------------------------------------------------------------------

  group('--remote', () {
    test('the default run never attempts a network call', () async {
      _writeFullyConfiguredProject(tempDir);
      final noNetwork = _NoNetworkDoctorCommand(tempDir.path);
      final ctx = ArtisanContext.bare(
        MapInput(
          {'verbose': false, 'remote': false},
          signature: noNetwork.parsedSignature,
        ),
        BufferedOutput(),
      );
      expect(await noNetwork.handle(ctx), 0);
    });

    test('a 200 JSON response for both files passes', () async {
      _writeValidConfig(tempDir, domain: 'app.example.com');
      final fake = _FakeRemoteDoctorCommand(tempDir.path, {
        'https://app.example.com/.well-known/apple-app-site-association':
            const RemoteAssociationFile(
          statusCode: 200,
          contentType: 'application/json',
          body: '{}',
        ),
        'https://app.example.com/.well-known/assetlinks.json':
            const RemoteAssociationFile(
          statusCode: 200,
          contentType: 'application/json',
          body: '[]',
        ),
      });

      final result = await fake.checkRemoteAssociationFiles();
      expect(result.issues, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('a non-200 status is reported as an issue', () async {
      _writeValidConfig(tempDir, domain: 'app.example.com');
      final fake = _FakeRemoteDoctorCommand(tempDir.path, {
        'https://app.example.com/.well-known/apple-app-site-association':
            const RemoteAssociationFile(
          statusCode: 302,
          contentType: null,
          body: '',
        ),
        'https://app.example.com/.well-known/assetlinks.json':
            const RemoteAssociationFile(
          statusCode: 200,
          contentType: 'application/json',
          body: '[]',
        ),
      });

      final result = await fake.checkRemoteAssociationFiles();
      expect(result.issues.any((i) => i.contains('302')), isTrue);
    });

    test('a body that does not parse as JSON is reported as an issue',
        () async {
      _writeValidConfig(tempDir, domain: 'app.example.com');
      final fake = _FakeRemoteDoctorCommand(tempDir.path, {
        'https://app.example.com/.well-known/apple-app-site-association':
            const RemoteAssociationFile(
          statusCode: 200,
          contentType: 'application/json',
          body: 'not json',
        ),
        'https://app.example.com/.well-known/assetlinks.json':
            const RemoteAssociationFile(
          statusCode: 200,
          contentType: 'application/json',
          body: '[]',
        ),
      });

      final result = await fake.checkRemoteAssociationFiles();
      expect(
          result.issues.any((i) => i.toLowerCase().contains('json')), isTrue);
    });

    test('a non-JSON content-type on the AASA is a warning, not a failure',
        () async {
      _writeValidConfig(tempDir, domain: 'app.example.com');
      final fake = _FakeRemoteDoctorCommand(tempDir.path, {
        'https://app.example.com/.well-known/apple-app-site-association':
            const RemoteAssociationFile(
          statusCode: 200,
          contentType: 'text/plain',
          body: '{}',
        ),
        'https://app.example.com/.well-known/assetlinks.json':
            const RemoteAssociationFile(
          statusCode: 200,
          contentType: 'application/json',
          body: '[]',
        ),
      });

      final result = await fake.checkRemoteAssociationFiles();
      expect(result.issues, isEmpty);
      expect(result.warnings.any((w) => w.contains('text/plain')), isTrue);
    });
  });

  group('the last mile no local check can prove', () {
    test('handle() output never claims device-side matching is verified',
        () async {
      _writeFullyConfiguredProject(tempDir);
      final output = BufferedOutput();
      final ctx = ArtisanContext.bare(
        MapInput(
          {'verbose': false, 'remote': false},
          signature: command.parsedSignature,
        ),
        output,
      );
      await command.handle(ctx);
      expect(output.content.toLowerCase(), contains('device'));
    });
  });
}
