# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### 📚 Documentation
- **README**: Rewrite to match Magic ecosystem format (centered logo, badges, features table, quick start)
- **doc/ folder**: Add comprehensive documentation (installation, configuration, drivers, handlers, CLI, architecture)

### 🔧 Improvements
- **Package naming**: Fix `fluttersdk_magic_deeplink` → `magic_deeplink` references for pub.dev publishing

## [0.0.1] - 2026-03-25

### ✨ Core Features
- **Unified Deep Link API**: Single interface for iOS Universal Links and Android App Links
- **Driver Pattern**: Extensible driver architecture with `AppLinksDriver` as default
- **Route Handler**: Automatically maps deep link paths to Magic Routes via `RouteDeeplinkHandler`
- **OneSignal Integration**: Seamless notification click → deep link handling via `OneSignalDeeplinkHandler`
- **CLI Tools**: `install` command generates config, `generate` command produces `apple-app-site-association` and `assetlinks.json`
- **Service Provider**: `DeeplinkServiceProvider` for automatic DI registration and boot
