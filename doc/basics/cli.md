# Magic Deeplink CLI

- [Introduction](#introduction)
- [Commands](#commands)
    - [install](#install)
    - [generate](#generate)
- [Config Merge Strategy](#config-merge-strategy)

<a name="introduction"></a>
## Introduction

Magic Deeplink ships a CLI that scaffolds deep link configuration into your project and generates the server-side verification files required by iOS Universal Links and Android App Links.

All commands are run via Dart's `run` mechanism:

```bash
dart run magic_deeplink:<command> [options]
```

<a name="commands"></a>
## Commands

<a name="install"></a>
### install

Scaffolds the deep link configuration file into the host project and wires it into the Magic app bootstrap automatically.

```bash
dart run magic_deeplink:install
dart run magic_deeplink:install --force
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
dart run magic_deeplink:generate \
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
    "apps": [],
    "details": [
      {
        "appID": "<team-id>.<bundle-id>",
        "paths": ["/*"]
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
