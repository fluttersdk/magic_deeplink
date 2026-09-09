import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

import 'generate_command.dart';

/// Diagnostic command for a `magic_deeplink` install.
///
/// The install has a half no manifest installer can automate: `artisan`'s
/// transactional DSL can publish files and inject lines, but it cannot place
/// an `<intent-filter>` inside a specific `<activity>` or tell an adopter
/// their `<meta-data>` landed on the wrong element. Every way of getting that
/// hand-written half wrong is SILENT: a deep link simply opens the browser,
/// with no exception and no log line anywhere. This command reads the
/// consumer's project files and says, before a device is ever involved,
/// which of the platform prerequisites are actually in place.
///
/// Checks are local and read-only by default. `--remote` additionally fetches
/// the two association files the app's own web host is expected to serve, to
/// confirm the SERVER side agrees with the config, not just the repo.
///
/// What this command can never prove: that a real device matches an incoming
/// link to this app. `swcutil verify` needs root and Android verifies at
/// install time, so the last mile is always a real device — [generateReport]
/// says so explicitly rather than letting a green run imply it.
///
/// ## Usage
/// ```bash
/// dart run <app>:artisan deeplink:doctor
/// dart run <app>:artisan deeplink:doctor --verbose
/// dart run <app>:artisan deeplink:doctor --remote
/// ```
class DoctorCommand extends ArtisanCommand {
  /// Values a scaffolded config still carries when nobody has filled them in.
  ///
  /// A published association file claiming one of these identities is worse
  /// than none: it tells a client the app has taken on responsibility for an
  /// identity nobody actually holds.
  static const Set<String> _placeholders = {
    'example.com',
    'YOUR_TEAM_ID',
    'com.example.app',
    'YOUR_SHA256_FINGERPRINT',
  };

  @override
  String get signature => 'deeplink:doctor '
      '{--verbose : Show detailed diagnostic information} '
      '{--remote : Also fetch the association files from the live domain}';

  @override
  String get description =>
      'Check magic_deeplink platform setup and configuration health';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// Absolute path to the Flutter project root, resolved on access.
  String get projectRoot => getProjectRoot();

  /// Resolve the Flutter project root — overridable in tests.
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Perform the actual GET request behind `--remote`.
  ///
  /// Overridable in tests so the default run never depends on network access.
  /// Redirects are not followed: a redirect answers as a non-200 status,
  /// which is already an issue this doctor reports.
  Future<RemoteAssociationFile> fetchRemoteFile(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return RemoteAssociationFile(
        statusCode: response.statusCode,
        contentType: response.headers.contentType?.mimeType,
        body: body,
      );
    } finally {
      client.close();
    }
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final verbose = ctx.input.option('verbose') as bool;
    final remote = ctx.input.option('remote') as bool;

    // 1. Remote checks are opt-in only — the default run never touches the
    //    network, so a doctor invoked in CI or offline never hangs on DNS.
    RemoteCheckResult? remoteResult;
    if (remote) {
      remoteResult = await checkRemoteAssociationFiles();
    }

    // 2. Collect local findings before printing — the report and the exit
    //    code both need the same lists.
    final missing = <String>[
      ...getMissingRequirements(),
      if (remoteResult != null)
        for (final issue in remoteResult.issues) '[remote] $issue',
    ];
    final warnings = <String>[
      ...getWarnings(),
      if (remoteResult != null)
        for (final warning in remoteResult.warnings) '[remote] $warning',
    ];

    ctx.output.writeln(
      generateReport(verbose: verbose, remoteResult: remoteResult),
    );

    // 3. Exit with the appropriate code. A warning alone exits 0: mixing
    //    AASA formats is discouraged, not broken, and a doctor that fails on
    //    it stops being read.
    if (missing.isEmpty && warnings.isEmpty) {
      ctx.output.success('All checks passed!');
      ctx.output.writeln('');
      return 0;
    }

    if (missing.isEmpty) {
      ctx.output.warning('Nothing failed, but see the warnings above.');
      ctx.output.writeln('');
      return 0;
    }

    ctx.output.writeln('');
    ctx.output.warning('Issues detected. Run the following to fix:');
    ctx.output.writeln('  • Install: dart run <app>:artisan deeplink:install');
    ctx.output
        .writeln('  • Generate: dart run <app>:artisan deeplink:generate');
    return 1;
  }

  // ---------------------------------------------------------------------------
  // Config
  // ---------------------------------------------------------------------------

  /// Path to the consumer's deep link config.
  String get _configPath => '$projectRoot/lib/config/deeplink.dart';

  /// Whether `lib/config/deeplink.dart` exists in the project root.
  bool checkConfigExists() => FileHelper.fileExists(_configPath);

  /// Parse [content] into the fields this doctor validates.
  ///
  /// Reuses [GenerateCommand.parseDeeplinkConfig] for `teamId`, `bundleId`,
  /// `packageName`, `fingerprints` and `paths` rather than scanning the file
  /// a second time: a doctor that reads the config differently from the
  /// generator could pass while the generator produces nothing. `domain` is
  /// added here because the generator never needed it — AASA/assetlinks
  /// content does not carry a host — but the platform checks below do.
  Map<String, dynamic> parseConfig(String content) {
    final config = GenerateCommand().parseDeeplinkConfig(content);

    final domainMatch = RegExp(r"'domain':\s*'([^']*)'").firstMatch(content);
    if (domainMatch != null) {
      config['domain'] = domainMatch.group(1);
    }

    return config;
  }

  /// [parseConfig] applied to the project's own config file, or empty when
  /// the file is missing.
  Map<String, dynamic> _loadConfig() {
    if (!checkConfigExists()) return const <String, dynamic>{};
    return parseConfig(FileHelper.readFile(_configPath));
  }

  /// Validate config presence and reject scaffold placeholders.
  ///
  /// Returns human-readable issue strings; empty means the config is usable.
  List<String> validateConfig() {
    if (!checkConfigExists()) {
      return ['Config file not found at lib/config/deeplink.dart'];
    }

    final config = parseConfig(FileHelper.readFile(_configPath));
    final issues = <String>[];

    final domain = config['domain'] as String?;
    if (domain == null || domain.isEmpty) {
      issues.add('deeplink.domain not found in config');
    } else if (_placeholders.contains(domain)) {
      issues.add('deeplink.domain is still the scaffold placeholder "$domain"');
    }

    final teamId = config['teamId'] as String?;
    if (teamId == null || teamId.isEmpty) {
      issues.add('ios.team_id not found in config');
    } else if (_placeholders.contains(teamId)) {
      issues.add('ios.team_id is still the scaffold placeholder "$teamId"');
    }

    final bundleId = config['bundleId'] as String?;
    if (bundleId == null || bundleId.isEmpty) {
      issues.add('ios.bundle_id not found in config');
    } else if (_placeholders.contains(bundleId)) {
      issues.add('ios.bundle_id is still the scaffold placeholder "$bundleId"');
    }

    final packageName = config['packageName'] as String?;
    if (packageName == null || packageName.isEmpty) {
      issues.add('android.package_name not found in config');
    } else if (_placeholders.contains(packageName)) {
      issues.add(
        'android.package_name is still the scaffold placeholder "$packageName"',
      );
    }

    final fingerprints = config['fingerprints'] as List<String>? ?? const [];
    if (fingerprints.isEmpty) {
      issues.add('android.sha256_fingerprints not found in config');
    } else {
      final placeholder = fingerprints.firstWhere(
        _placeholders.contains,
        orElse: () => '',
      );
      if (placeholder.isNotEmpty) {
        issues.add(
          'android.sha256_fingerprints still contains the scaffold placeholder "$placeholder"',
        );
      }
    }

    return issues;
  }

  // ---------------------------------------------------------------------------
  // Dart wiring
  // ---------------------------------------------------------------------------

  /// Whether the Dart half of the install actually reached the app.
  ///
  /// Every other section here checks a platform file, and all of them can pass
  /// on a project where this package is a dependency and nothing more: the
  /// entitlement, the intent filter and both association files are correct, the
  /// domain resolves, and no link ever opens the app because no provider was
  /// registered. That is the state a half-applied install leaves behind, and
  /// it is also what a human gets by adding the dependency by hand, so a green
  /// report that cannot see it is the most misleading answer this command can
  /// give.
  ///
  /// Three things, each of which alone makes the feature inert:
  /// the provider in `lib/config/app.dart`, the config factory in
  /// `lib/main.dart`, and at least one `registerHandler` call somewhere under
  /// `lib/`. The last is a WARNING rather than a failure: a consumer may
  /// register handlers from a provider this scan cannot recognise, and failing
  /// a correct project is worse than under-reporting on an unusual one.
  Map<String, dynamic> checkWiring() {
    final issues = <String>[];
    final warnings = <String>[];

    final appConfig = '$projectRoot/lib/config/app.dart';
    if (!FileHelper.fileExists(appConfig)) {
      issues.add('lib/config/app.dart not found, so the provider list could '
          'not be read');
    } else if (!_mentions(appConfig, 'DeeplinkServiceProvider')) {
      issues.add('DeeplinkServiceProvider is not registered in '
          'lib/config/app.dart. Without it no driver is created and no link '
          'ever reaches a handler.');
    }

    final main = '$projectRoot/lib/main.dart';
    if (!FileHelper.fileExists(main)) {
      issues.add('lib/main.dart not found, so the config factory could not be '
          'read');
    } else if (!_mentions(main, 'deeplinkConfig')) {
      issues.add('deeplinkConfig is not passed to Magic.init in lib/main.dart. '
          'Every value this report just validated is then invisible at '
          'runtime.');
    }

    if (!_libMentions('registerHandler(')) {
      warnings.add('No registerHandler( call found under lib/. A link that '
          'reaches the manager with no handler registered is dropped without '
          'an error. Ignore this if handlers are registered somewhere this '
          'scan cannot see.');
    }

    return {
      'configured': issues.isEmpty,
      'exists': true,
      'issues': issues,
      'warnings': warnings,
    };
  }

  /// Whether [path] contains [needle] outside a `//` line comment.
  ///
  /// Comments are stripped for the same reason the Android checks strip XML
  /// ones: a commented-out registration reads identically to a live one, and
  /// that is exactly the state a half-finished install leaves behind.
  bool _mentions(String path, String needle) =>
      _stripLineComments(FileHelper.readFile(path)).contains(needle);

  /// Whether any Dart file under `lib/` contains [needle], comments aside.
  bool _libMentions(String needle) {
    final lib = Directory('$projectRoot/lib');
    if (!lib.existsSync()) return false;

    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      try {
        if (_stripLineComments(entity.readAsStringSync()).contains(needle)) {
          return true;
        }
      } on FileSystemException {
        // An unreadable file is not evidence of absence, and refusing to
        // finish the sweep over one would turn a permissions quirk into a
        // failed doctor run.
        continue;
      }
    }

    return false;
  }

  /// [source] with `//` line comments removed.
  String _stripLineComments(String source) => source.split('\n').map((line) {
        final marker = line.indexOf('//');
        return marker == -1 ? line : line.substring(0, marker);
      }).join('\n');

  // ---------------------------------------------------------------------------
  // Platform setup
  // ---------------------------------------------------------------------------

  /// Check platform-specific setup plus the association files.
  ///
  /// iOS and Android sections only appear when that platform's directory
  /// exists; the association-files section always runs, since a project can
  /// host `.well-known/` files without shipping the corresponding Flutter
  /// platform folder.
  Map<String, dynamic> checkPlatformSetup() {
    final config = _loadConfig();
    final platforms = PlatformHelper.detectPlatforms(projectRoot);
    final result = <String, dynamic>{'wiring': checkWiring()};

    if (platforms.contains('ios')) {
      result['ios'] = _checkIosSetup(config);
    }

    if (platforms.contains('android')) {
      result['android'] = _checkAndroidSetup(config);
    }

    result['associations'] = _checkAssociationFiles(config);

    return result;
  }

  // ---------------------------------------------------------------------------
  // iOS
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _checkIosSetup(Map<String, dynamic> config) {
    final infoPlistPath = PlatformHelper.infoPlistPath(projectRoot);

    if (!FileHelper.fileExists(infoPlistPath)) {
      return {
        'configured': false,
        'exists': false,
        'issues': ['Info.plist not found'],
        'warnings': <String>[],
      };
    }

    final issues = <String>[];
    final infoPlist = _withoutComments(FileHelper.readFile(infoPlistPath));

    // 4. Flutter has handled deep links itself by default since 3.27; when it
    //    does, the plugin's handler chain never sees the link.
    final deepLinkingMatch = RegExp(
      r'<key>\s*FlutterDeepLinkingEnabled\s*</key>\s*<(true|false)\s*/>',
    ).firstMatch(infoPlist);
    if (deepLinkingMatch == null) {
      issues.add(
        'FlutterDeepLinkingEnabled is missing from ios/Runner/Info.plist. '
        'Flutter has handled deep links itself by default since 3.27, so the '
        'plugin handler chain never sees the link until this is set to false.',
      );
    } else if (deepLinkingMatch.group(1) != 'false') {
      issues.add(
        'FlutterDeepLinkingEnabled is true in ios/Runner/Info.plist, expected false',
      );
    }

    // 3. The entitlements host must equal deeplink.domain, or a Universal
    //    Link for the configured domain will never reach this app.
    final entitlementsPath = '$projectRoot/ios/Runner/Runner.entitlements';
    if (!FileHelper.fileExists(entitlementsPath)) {
      issues.add(
          'Runner.entitlements not found at ios/Runner/Runner.entitlements');
    } else {
      final entitlements =
          _withoutComments(FileHelper.readFile(entitlementsPath));
      final arrayMatch = RegExp(
        r'<key>\s*com\.apple\.developer\.associated-domains\s*</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(entitlements);

      if (arrayMatch == null) {
        issues.add(
          'com.apple.developer.associated-domains entitlement not found in '
          'Runner.entitlements',
        );
      } else {
        final hosts = RegExp(r'applinks:([\w.-]+)')
            .allMatches(arrayMatch.group(1)!)
            .map((m) => m.group(1)!)
            .toSet();
        final domain = config['domain'] as String?;
        if (domain != null && domain.isNotEmpty && !hosts.contains(domain)) {
          issues.add(
            'associated-domains host ${hosts.isEmpty ? '(none)' : hosts.join(', ')} '
            'does not match deeplink.domain "$domain"',
          );
        }
      }
    }

    return {
      'configured': issues.isEmpty,
      'exists': true,
      'issues': issues,
      'warnings': <String>[],
    };
  }

  // ---------------------------------------------------------------------------
  // Android
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _checkAndroidSetup(Map<String, dynamic> config) {
    final manifestPath = PlatformHelper.androidManifestPath(projectRoot);

    if (!FileHelper.fileExists(manifestPath)) {
      return {
        'configured': false,
        'exists': false,
        'issues': ['AndroidManifest.xml not found'],
        'warnings': <String>[],
      };
    }

    final manifest = _withoutComments(FileHelper.readFile(manifestPath));
    final applicationBody = _applicationBlock(manifest);
    if (applicationBody == null) {
      return {
        'configured': false,
        'exists': true,
        'issues': ['<application> element not found in AndroidManifest.xml'],
        'warnings': <String>[],
      };
    }

    // 1. Split the application body into "direct children" and each
    //    <activity>'s own body, so a <meta-data> can be told apart by TREE
    //    POSITION rather than by a substring search that greps the same on
    //    either element.
    final activityRegex = RegExp(
      r'<activity\b[^>]*>(.*?)</activity>',
      dotAll: true,
    );
    final activityMatches = activityRegex.allMatches(applicationBody).toList();
    final activityBodies = activityMatches.map((m) => m.group(1)!).toList();
    var directChildren = applicationBody;
    for (final match in activityMatches) {
      directChildren = directChildren.replaceFirst(match.group(0)!, '');
    }

    final issues = <String>[
      ..._checkFlutterDeeplinkingMetaData(activityBodies, directChildren),
      ..._checkAutoVerifyIntentFilter(
          activityBodies, config['domain'] as String?),
    ];

    return {
      'configured': issues.isEmpty,
      'exists': true,
      'issues': issues,
      'warnings': <String>[],
    };
  }

  /// Extract the `<application>...</application>` body, or `null` when the
  /// manifest carries no `<application>` element.
  String? _applicationBlock(String manifest) {
    return RegExp(
      r'<application\b[^>]*>(.*?)</application>',
      dotAll: true,
    ).firstMatch(manifest)?.group(1);
  }

  /// Whether any self-closed `<meta-data>` element in [body] names [name],
  /// and if so, the value of its `android:value` attribute.
  String? _metaDataValue(String body, String name) {
    final nameRegex = RegExp('android:name\\s*=\\s*"${RegExp.escape(name)}"');
    for (final match in RegExp(r'<meta-data\b([^>]*?)/>').allMatches(body)) {
      final attrs = match.group(1)!;
      if (!nameRegex.hasMatch(attrs)) continue;
      return RegExp(r'android:value\s*=\s*"([^"]*)"')
          .firstMatch(attrs)
          ?.group(1);
    }
    return null;
  }

  /// 6. `flutter_deeplinking_enabled` must be `false` and sit inside an
  /// `<activity>`, never inside `<application>` — the failure mode this
  /// command exists to catch, since both locations grep identically.
  List<String> _checkFlutterDeeplinkingMetaData(
    List<String> activityBodies,
    String directChildren,
  ) {
    const key = 'flutter_deeplinking_enabled';

    if (_metaDataValue(directChildren, key) != null) {
      return [
        '$key meta-data is declared inside <application>, not <activity>. '
            'Flutter only reads it on the activity element, so it is inert '
            'here and Flutter\'s own deep link handler stays in the way.',
      ];
    }

    String? value;
    for (final body in activityBodies) {
      value = _metaDataValue(body, key);
      if (value != null) break;
    }

    if (value == null) {
      return [
        '$key meta-data not found inside any <activity> in AndroidManifest.xml'
      ];
    }
    if (value != 'false') {
      return [
        '$key is "$value" inside <activity>, expected "false" so the plugin '
            'handler chain receives the link',
      ];
    }
    return const [];
  }

  /// 5. An `<intent-filter android:autoVerify="true">` inside an `<activity>`
  /// must carry `VIEW`, `DEFAULT`, `BROWSABLE`, `<data>` for both `http` and
  /// `https`, and a host equal to `deeplink.domain`. Google's own guidance:
  /// "The intent filter must include `<data>` elements for both `http` and
  /// `https` schemes."
  List<String> _checkAutoVerifyIntentFilter(
    List<String> activityBodies,
    String? domain,
  ) {
    final filterRegex = RegExp(
      r'<intent-filter\b([^>]*)>(.*?)</intent-filter>',
      dotAll: true,
    );

    RegExpMatch? autoVerifyFilter;
    for (final activityBody in activityBodies) {
      for (final match in filterRegex.allMatches(activityBody)) {
        if (RegExp('android:autoVerify\\s*=\\s*"true"')
            .hasMatch(match.group(1)!)) {
          autoVerifyFilter = match;
          break;
        }
      }
      if (autoVerifyFilter != null) break;
    }

    if (autoVerifyFilter == null) {
      return [
        'No <intent-filter android:autoVerify="true"> found inside an <activity>',
      ];
    }

    final issues = <String>[];
    final body = autoVerifyFilter.group(2)!;

    if (!body.contains('android.intent.action.VIEW')) {
      issues.add(
          'autoVerify intent-filter is missing an android.intent.action.VIEW <action>');
    }
    if (!body.contains('android.intent.category.DEFAULT')) {
      issues.add(
        'autoVerify intent-filter is missing an android.intent.category.DEFAULT <category>',
      );
    }
    if (!body.contains('android.intent.category.BROWSABLE')) {
      issues.add(
        'autoVerify intent-filter is missing an android.intent.category.BROWSABLE <category>',
      );
    }

    final schemes = RegExp(r'android:scheme\s*=\s*"([^"]*)"')
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toSet();
    if (!schemes.contains('http')) {
      issues.add(
          'autoVerify intent-filter is missing a <data android:scheme="http"/> element');
    }
    if (!schemes.contains('https')) {
      issues.add(
        'autoVerify intent-filter is missing a <data android:scheme="https"/> element',
      );
    }

    if (domain != null && domain.isNotEmpty) {
      final hosts = RegExp(r'android:host\s*=\s*"([^"]*)"')
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet();
      if (!hosts.contains(domain)) {
        issues.add(
          'autoVerify intent-filter host ${hosts.isEmpty ? '(none)' : hosts.join(', ')} '
          'does not match deeplink.domain "$domain"',
        );
      }
    }

    return issues;
  }

  /// Strip XML comments before any structural search runs, so a commented-out
  /// element does not count as configuration.
  String _withoutComments(String source) =>
      source.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  // ---------------------------------------------------------------------------
  // Association files
  // ---------------------------------------------------------------------------

  /// 7. The generated association files must exist and agree with the config.
  Map<String, dynamic> _checkAssociationFiles(Map<String, dynamic> config) {
    final issues = <String>[];
    final warnings = <String>[];

    final teamId = config['teamId'] as String?;
    final bundleId = config['bundleId'] as String?;
    final packageName = config['packageName'] as String?;
    final fingerprints = config['fingerprints'] as List<String>? ?? const [];

    final aasaPath = _findAssociationFile('apple-app-site-association');
    if (aasaPath == null) {
      issues.add(
        'apple-app-site-association not found under web/.well-known/ or public/.well-known/',
      );
    } else {
      final result = _validateAasa(aasaPath, teamId, bundleId);
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
    }

    final assetLinksPath = _findAssociationFile('assetlinks.json');
    if (assetLinksPath == null) {
      issues.add(
        'assetlinks.json not found under web/.well-known/ or public/.well-known/',
      );
    } else {
      issues.addAll(
          _validateAssetLinks(assetLinksPath, packageName, fingerprints));
    }

    return {
      'configured': issues.isEmpty,
      'exists': aasaPath != null || assetLinksPath != null,
      'issues': issues,
      'warnings': warnings,
    };
  }

  /// First existing path for [fileName] under `web/.well-known/` or
  /// `public/.well-known/`, or `null` when neither exists.
  String? _findAssociationFile(String fileName) {
    for (final dir in const ['web', 'public']) {
      final path = '$projectRoot/$dir/.well-known/$fileName';
      if (FileHelper.fileExists(path)) return path;
    }
    return null;
  }

  /// Validate an `apple-app-site-association` file's content against
  /// [teamId] + [bundleId], and warn on a legacy/modern format mix.
  RemoteCheckResult _validateAasa(
      String path, String? teamId, String? bundleId) {
    final issues = <String>[];
    final warnings = <String>[];

    final dynamic decoded;
    try {
      decoded = jsonDecode(FileHelper.readFile(path));
    } on FormatException {
      issues.add('apple-app-site-association at $path is not valid JSON');
      return RemoteCheckResult(issues, warnings);
    }

    dynamic details;
    if (decoded is Map) {
      final applinks = decoded['applinks'];
      if (applinks is Map) {
        details = applinks['details'];
      }
    }
    if (details is! List) {
      issues.add(
          'apple-app-site-association at $path has no applinks.details entries');
      return RemoteCheckResult(issues, warnings);
    }

    final appIds = <String>{};
    var hasModern = false;
    var hasLegacy = false;
    for (final detail in details) {
      if (detail is! Map) continue;
      if (detail['appIDs'] is List) {
        hasModern = true;
        appIds.addAll((detail['appIDs'] as List).whereType<String>());
      }
      if (detail['appID'] is String) {
        hasLegacy = true;
        appIds.add(detail['appID'] as String);
      }
    }

    // Apple's TN3155: "Please avoid mixing formats. Doing so may result in
    // unexpected behavior for universal links." A warning, not a failure —
    // both formats individually work.
    if (hasModern && hasLegacy) {
      warnings.add(
        'apple-app-site-association at $path mixes the legacy appID+paths '
        'format with the modern appIDs+components format; Apple\'s TN3155 '
        'warns this may produce unexpected universal link behaviour',
      );
    }

    if (teamId != null &&
        bundleId != null &&
        teamId.isNotEmpty &&
        bundleId.isNotEmpty) {
      final expected = '$teamId.$bundleId';
      if (!appIds.contains(expected)) {
        issues.add(
          'apple-app-site-association at $path does not claim "$expected" '
          '(team_id.bundle_id); found: ${appIds.isEmpty ? '(none)' : appIds.join(', ')}',
        );
      }
    }

    return RemoteCheckResult(issues, warnings);
  }

  /// Validate an `assetlinks.json` file's content against [packageName] +
  /// [fingerprints].
  List<String> _validateAssetLinks(
    String path,
    String? packageName,
    List<String> fingerprints,
  ) {
    final issues = <String>[];

    final dynamic decoded;
    try {
      decoded = jsonDecode(FileHelper.readFile(path));
    } on FormatException {
      issues.add('assetlinks.json at $path is not valid JSON');
      return issues;
    }

    if (decoded is! List) {
      issues.add('assetlinks.json at $path is not a JSON array');
      return issues;
    }

    final packageNames = <String>{};
    final seenFingerprints = <String>{};
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final target = entry['target'];
      if (target is! Map) continue;
      if (target['package_name'] is String) {
        packageNames.add(target['package_name'] as String);
      }
      final certs = target['sha256_cert_fingerprints'];
      if (certs is List) {
        seenFingerprints.addAll(certs.whereType<String>());
      }
    }

    if (packageName != null &&
        packageName.isNotEmpty &&
        !packageNames.contains(packageName)) {
      issues.add(
        'assetlinks.json at $path does not list package_name "$packageName"; '
        'found: ${packageNames.isEmpty ? '(none)' : packageNames.join(', ')}',
      );
    }

    for (final fingerprint in fingerprints) {
      if (!seenFingerprints.contains(fingerprint)) {
        issues.add(
            'assetlinks.json at $path is missing the sha256 fingerprint "$fingerprint"');
      }
    }

    return issues;
  }

  // ---------------------------------------------------------------------------
  // Remote (--remote only)
  // ---------------------------------------------------------------------------

  /// GET both association files from the live domain and check status,
  /// JSON-parseability, and (for the AASA) content-type.
  ///
  /// Never called unless `--remote` is passed: a doctor that hangs on DNS is
  /// a doctor nobody runs.
  Future<RemoteCheckResult> checkRemoteAssociationFiles() async {
    final domain = _loadConfig()['domain'] as String?;
    if (domain == null || domain.isEmpty) {
      return const RemoteCheckResult(
        ['--remote requires deeplink.domain to be configured'],
        [],
      );
    }

    final issues = <String>[];
    final warnings = <String>[];

    for (final fileName in const [
      'apple-app-site-association',
      'assetlinks.json',
    ]) {
      final uri = Uri.parse('https://$domain/.well-known/$fileName');
      try {
        final result = await fetchRemoteFile(uri);

        if (result.statusCode != 200) {
          issues.add(
              '$uri responded ${result.statusCode}, expected 200 with no redirect');
          continue;
        }

        try {
          jsonDecode(result.body);
        } on FormatException {
          issues.add('$uri did not return a body that parses as JSON');
        }

        if (fileName == 'apple-app-site-association' &&
            result.contentType != 'application/json') {
          warnings.add(
            '$uri served content-type "${result.contentType}", expected application/json',
          );
        }
      } on Exception catch (e) {
        issues.add('$uri could not be reached: $e');
      }
    }

    return RemoteCheckResult(issues, warnings);
  }

  // ---------------------------------------------------------------------------
  // Report
  // ---------------------------------------------------------------------------

  /// Every unmet requirement across config, platform, and association checks.
  List<String> getMissingRequirements() {
    final missing = <String>[];

    if (!checkConfigExists()) {
      missing.add('Configuration file not found (lib/config/deeplink.dart)');
      return missing;
    }

    missing.addAll(validateConfig());

    for (final entry in checkPlatformSetup().entries) {
      final status = entry.value as Map<String, dynamic>;
      for (final issue in status['issues'] as List) {
        missing.add('[${entry.key}] $issue');
      }
    }

    return missing;
  }

  /// Everything configured correctly that still deserves a second look —
  /// currently only a mixed-format association file. Never fails the
  /// command; a doctor that always fails gets ignored.
  List<String> getWarnings() {
    if (!checkConfigExists()) return const [];

    final associations =
        checkPlatformSetup()['associations'] as Map<String, dynamic>?;
    if (associations == null) return const [];

    return List<String>.from(associations['warnings'] as List? ?? const []);
  }

  /// Generate a human-readable diagnostic report.
  ///
  /// [remoteResult] is included only when `--remote` was requested; the
  /// closing note names the one thing no local (or remote) check can ever
  /// prove: that a real device matches the link.
  String generateReport(
      {bool verbose = false, RemoteCheckResult? remoteResult}) {
    final buffer = StringBuffer();
    buffer.writeln('Magic Deeplink — Doctor Report');
    buffer.writeln('=' * 50);
    buffer.writeln();

    final configExists = checkConfigExists();
    buffer.writeln('Configuration File: ${configExists ? '✓' : '✗'}');
    if (verbose) {
      buffer.writeln('    Path: lib/config/deeplink.dart');
    }
    buffer.writeln();

    buffer.writeln('Config Validation:');
    if (!configExists) {
      buffer.writeln('  ✗ Skipped — config file missing');
    } else {
      final configIssues = validateConfig();
      if (configIssues.isEmpty) {
        buffer.writeln('  ✓ All config checks passed');
      } else {
        for (final issue in configIssues) {
          buffer.writeln('  ✗ $issue');
        }
      }
    }
    buffer.writeln();

    final platformStatus =
        configExists ? checkPlatformSetup() : <String, dynamic>{};
    if (platformStatus.isEmpty) {
      if (configExists) {
        buffer.writeln('Platform Setup: no platforms detected');
        buffer.writeln();
      }
    } else {
      for (final entry in platformStatus.entries) {
        final section = entry.key;
        final status = entry.value as Map<String, dynamic>;
        final configured = status['configured'] as bool;
        final exists = status['exists'] as bool;
        final issues = status['issues'] as List;
        final warnings = status['warnings'] as List? ?? const [];

        buffer.write('${_sectionTitle(section)}: ');
        if (configured && warnings.isEmpty) {
          buffer.writeln('✓ Configured');
        } else if (exists) {
          buffer.writeln('⚠ Needs attention');
        } else {
          buffer.writeln('✗ Not found');
        }

        if (verbose) {
          for (final issue in issues) {
            buffer.writeln('    ✗ $issue');
          }
          for (final warning in warnings) {
            buffer.writeln('    ⚠ $warning');
          }
        }
      }
      buffer.writeln();
    }

    if (remoteResult != null) {
      buffer.writeln('Remote (--remote):');
      if (remoteResult.issues.isEmpty && remoteResult.warnings.isEmpty) {
        buffer.writeln('  ✓ Both association files served correctly');
      } else {
        for (final issue in remoteResult.issues) {
          buffer.writeln('  ✗ $issue');
        }
        for (final warning in remoteResult.warnings) {
          buffer.writeln('  ⚠ $warning');
        }
      }
      buffer.writeln();
    }

    final missing = configExists ? getMissingRequirements() : validateConfig();
    final warnings = configExists ? getWarnings() : const <String>[];
    final allIssues = [
      ...missing,
      ...remoteResult?.issues.map((i) => '[remote] $i') ?? const <String>[],
    ];
    final allWarnings = [
      ...warnings,
      ...remoteResult?.warnings.map((w) => '[remote] $w') ?? const <String>[],
    ];

    if (allIssues.isEmpty && allWarnings.isEmpty) {
      buffer.writeln('✓ All requirements met!');
    }

    if (allIssues.isNotEmpty) {
      buffer.writeln('Missing Requirements:');
      for (final issue in allIssues) {
        buffer.writeln('  ✗ $issue');
      }
    }

    if (allWarnings.isNotEmpty) {
      buffer.writeln('Warnings:');
      for (final warning in allWarnings) {
        buffer.writeln('  ⚠ $warning');
      }
    }

    buffer.writeln();
    buffer.writeln(
      'Note: no local check can prove a device actually matches this link. '
      '`swcutil verify` needs root and Android verifies at install time — the '
      'last mile is always a real device.',
    );

    return buffer.toString();
  }

  /// Human title for a [checkPlatformSetup] section key.
  String _sectionTitle(String section) => switch (section) {
        'wiring' => 'Dart Wiring',
        'ios' => 'iOS Setup',
        'android' => 'Android Setup',
        'associations' => 'Association Files',
        _ => section,
      };
}

/// A `--remote` HTTP response, trimmed to what the doctor checks: status,
/// content-type, and the raw body to attempt a JSON parse against.
class RemoteAssociationFile {
  final int statusCode;
  final String? contentType;
  final String body;

  const RemoteAssociationFile({
    required this.statusCode,
    required this.contentType,
    required this.body,
  });
}

/// Findings from validating a file or a remote fetch: hard failures that
/// fail the command, and warnings that do not.
class RemoteCheckResult {
  final List<String> issues;
  final List<String> warnings;

  const RemoteCheckResult(this.issues, this.warnings);
}
