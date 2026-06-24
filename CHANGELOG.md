# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.0.1] - 2026-06-24

### 💥 Breaking Changes
- **Removed bin/ entrypoint**: `dart run magic_deeplink:install` / `dart run magic_deeplink:generate` no longer available. Use host-dispatched artisan commands instead: `dart run <app>:artisan deeplink:install` and `dart run <app>:artisan deeplink:generate`. This requires adding `MagicDeeplinkArtisanProvider` to your app's artisan providers list (see CLAUDE.md for setup).
- **Removed magic_cli dependency**: Commands now extend `ArtisanCommand` from `fluttersdk_artisan` instead of `Command` from `magic_cli`.

### ✨ Improvements
- **Manifest-driven install**: The `deeplink:install` command is now powered by `install.yaml` and the artisan transactional installer, replacing imperative setup code. This enables consistent scaffolding across all magic plugins.
- **Read-only MCP tools**: none. magic_deeplink ships only mutating commands (install, generate) and registers no MCP tools.

### 📚 Documentation
- **README**: Rewrite to match Magic ecosystem format (centered logo, badges, features table, quick start)
- **doc/ folder**: Add comprehensive documentation (installation, configuration, drivers, handlers, CLI, architecture)
- **CLAUDE.md**: Updated architecture section and command table to reflect artisan dispatch model

### 🔧 Improvements
- **Package naming**: Fix `fluttersdk_magic_deeplink` → `magic_deeplink` references for pub.dev publishing

## [0.0.1-alpha.1] - 2026-03-25

### ✨ Core Features
- **Unified Deep Link API**: Single interface for iOS Universal Links and Android App Links
- **Driver Pattern**: Extensible driver architecture with `AppLinksDriver` as default
- **Route Handler**: Automatically maps deep link paths to Magic Routes via `RouteDeeplinkHandler`
- **OneSignal Integration**: Seamless notification click → deep link handling via `OneSignalDeeplinkHandler`
- **CLI Tools**: `install` command generates config, `generate` command produces `apple-app-site-association` and `assetlinks.json`
- **Service Provider**: `DeeplinkServiceProvider` for automatic DI registration and boot
