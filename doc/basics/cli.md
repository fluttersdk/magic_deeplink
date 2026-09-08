# Magic Deeplink CLI

- [Introduction](#introduction)
- [Commands](#commands)
    - [install](#install)
    - [generate](#generate)
    - [doctor](#doctor)
- [Config Merge Strategy](#config-merge-strategy)

<a name="introduction"></a>
## Introduction

Magic Deeplink ships a CLI that scaffolds deep link configuration into your project and generates the server-side verification files required by iOS Universal Links and Android App Links.

All commands are run via Dart's `run` mechanism:

```bash
dart run <app>:artisan deeplink:<command> [options]
```

<a name="commands"></a>
## Commands

<a name="install"></a>
### install

Scaffolds the deep link configuration file into the host project and wires it into the Magic app bootstrap automatically.

```bash
dart run <app>:artisan deeplink:install
dart run <app>:artisan deeplink:install --force
```

#### What it does

1. Validates that Magic Framework is installed by checking for `lib/config/app.dart`. If the file is absent it exits with an error: `Magic Framework not detected. Run 'magic install' first.`
2. Writes `lib/config/deeplink.dart` from the built-in stub. Skips the write when the file already exists unless `--force` is passed.
3. Injects into `lib/config/app.dart`:
   - Import: `import 'package:magic_deeplink/magic_deeplink.dart';`
   - Provider registration: `(app) => DeeplinkServiceProvider(app),`
4. Injects into `lib/main.dart` (when present):
   - Import: `import 'config/deeplink.dart';`
   - Config factory: `() => deeplinkConfig,`

All injections are idempotent — running the command twice does not duplicate entries.

#### Options

| Flag | Abbr | Type | Default | Description |
|------|------|------|---------|-------------|
| `--force` | `-f` | bool | `false` | Overwrite `lib/config/deeplink.dart` even if it already exists. |

#### Output files

| File | Action |
|------|--------|
| `lib/config/deeplink.dart` | Created (or overwritten with `--force`) |
| `lib/config/app.dart` | Import + `DeeplinkServiceProvider` injected |
| `lib/main.dart` | Import + `deeplinkConfig` factory injected |

<a name="generate"></a>
### generate

Generates the server-side deep link verification files: `apple-app-site-association` for iOS Universal Links and `assetlinks.json` for Android App Links.

```bash
dart run <app>:artisan deeplink:generate \
  --team-id ABCDE12345 \
  --bundle-id com.example.app \
  --package-name com.example.app \
  --sha256-fingerprints "AA:BB:CC:DD:..." \
  --output public
```

Both files can be generated in one invocation, or individually by omitting the flags for the platform you don't need.

#### Options

| Option | Abbr | Type | Default | Description |
|--------|------|------|---------|-------------|
| `--output` | `-o` | string | `public` | Output directory for generated files, relative to the project root. |
| `--root` | — | string | `.` | Override the project root directory. Defaults to the current working directory. |
| `--team-id` | — | string | — | Apple Developer Team ID. Required to generate `apple-app-site-association`. |
| `--bundle-id` | — | string | — | iOS app bundle identifier. Required to generate `apple-app-site-association`. |
| `--package-name` | — | string | — | Android package name. Required to generate `assetlinks.json`. |
| `--sha256-fingerprints` | — | list | — | One or more SHA-256 certificate fingerprints. Pass the flag multiple times or comma-separate values. Required to generate `assetlinks.json`. |
| `--paths` | — | list | `['/*']` | Universal Link and App Link paths to register. Defaults to all paths (`/*`). |

#### Output files

| File | Platform | Required flags |
|------|----------|----------------|
| `<output>/apple-app-site-association` | iOS Universal Links | `--team-id`, `--bundle-id` |
| `<output>/assetlinks.json` | Android App Links | `--package-name`, `--sha256-fingerprints` |

If the required flags for a platform are absent the command skips that file with a warning rather than failing, allowing you to generate only one platform's file at a time.

#### Generated file structure

`apple-app-site-association`:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["<team-id>.<bundle-id>"],
        "components": [
          { "/": "/*", "comment": "Matches any URL whose path matches /*" }
        ]
      }
    ]
  }
}
```

`assetlinks.json` (one entry per fingerprint):

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.example.app",
      "sha256_cert_fingerprints": ["AA:BB:CC:DD:..."]
    }
  }
]
```

<a name="doctor"></a>
### doctor

Checks whether a deep link install actually works, before a device is ever involved.

Manifest-driven install can publish the config file and inject a provider, but it cannot place an `<intent-filter>` inside a specific `<activity>` or tell you a `<meta-data>` landed on the wrong element. Every way of getting that hand-written half of the setup wrong is silent: a deep link simply opens the browser, with no exception and no log line anywhere.

```bash
dart run <app>:artisan deeplink:doctor
dart run <app>:artisan deeplink:doctor --verbose
dart run <app>:artisan deeplink:doctor --remote
```

#### What it checks

Local checks, always run:

1. `lib/config/deeplink.dart` exists and parses (reusing the same parser `generate` uses), and none of `domain`, `team_id`, `bundle_id`, `package_name`, `sha256_fingerprints` are still a scaffold placeholder (`example.com`, `YOUR_TEAM_ID`, `com.example.app`, `YOUR_SHA256_FINGERPRINT`).
2. iOS: `Runner.entitlements` carries `com.apple.developer.associated-domains`, and its `applinks:` host equals `deeplink.domain`.
3. iOS: `FlutterDeepLinkingEnabled` is `false` in `Info.plist`. Flutter has handled deep links itself by default since 3.27, and when it does, this plugin's handler chain never sees the link.
4. Android: an `<intent-filter android:autoVerify="true">` inside the activity carries `VIEW`, `DEFAULT`, `BROWSABLE`, `<data>` elements for both `http` and `https`, and a host equal to `deeplink.domain`.
5. Android: `flutter_deeplinking_enabled` is `false` and sits inside `<activity>`, not `<application>`. This is parsed off the manifest's element tree rather than searched for as text — a `<meta-data>` in the wrong element greps identically to one in the right one and is inert.
6. The generated association files exist under `web/.well-known/` or `public/.well-known/`, and their contents agree with the config: the AASA's `appIDs` entry equals `<team_id>.<bundle_id>`, and `assetlinks.json`'s `package_name` and fingerprints match. A legacy `appID`+`paths` AASA entry mixed with a modern `appIDs`+`components` one in the same file is a warning, not a failure (Apple's TN3155 says mixing formats "may result in unexpected behavior").

Remote check, only with `--remote`:

7. `GET https://<domain>/.well-known/apple-app-site-association` and `.../assetlinks.json` — both must answer 200 with no redirect and a body that parses as JSON. A non-`application/json` content-type on the AASA is a warning.

#### What it cannot prove

No local or remote check can prove a device actually matches a link: `swcutil verify` needs root and Android verifies at install time. The report says so explicitly rather than letting a green run imply it. Verify the last mile on a real device.

#### Options

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--verbose` | bool | `false` | Show per-issue detail under each section. |
| `--remote` | bool | `false` | Also fetch both association files from the live domain. Never runs by default — a doctor that hangs on DNS is a doctor nobody runs. |

#### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Every check passed (or only warnings were raised). |
| `1` | At least one check failed. |

<a name="config-merge-strategy"></a>
## Config Merge Strategy

The `generate` command reads `lib/config/deeplink.dart` automatically when the file exists. Values from the config file act as defaults — any flag passed on the command line takes precedence.

| Source | Priority |
|--------|----------|
| CLI flag | High — always wins |
| `lib/config/deeplink.dart` | Low — used when the corresponding CLI flag is absent or empty |

Config keys read from `lib/config/deeplink.dart`:

| Config key | Corresponding CLI flag |
|------------|----------------------|
| `team_id` | `--team-id` |
| `bundle_id` | `--bundle-id` |
| `package_name` | `--package-name` |
| `sha256_fingerprints` | `--sha256-fingerprints` |
| `paths` | `--paths` |

The `--paths` flag is special: its CLI default is `['/*']`. The config file value only overrides this default when the CLI flag was not explicitly supplied and the config contains a non-empty paths list. Passing `--paths` on the command line always wins, even if the config file defines paths.

This means you can commit all platform identifiers in `lib/config/deeplink.dart` and run `generate` with no flags during CI, while still being able to override individual values ad-hoc.
