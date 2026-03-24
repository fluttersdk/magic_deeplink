---
path: "test/**/*.dart"
---

# Testing Domain

- Mock via contract inheritance (no mockito): `class MockDeeplinkDriver extends DeeplinkDriver { ... }`
- Mock handlers: constructor params `canHandleValue` / `handleValue` control behavior, `handleCalled` flag for assertion
- Mock drivers: override `name`, `isSupported`, `onLink` (return `Stream.empty()`), `initialize()`, `getInitialLink()`
- Reset singleton state in setUp: `manager.forgetHandlers()`, `manager.forgetDriver()`
- Test structure mirrors `lib/src/` exactly: `test/drivers/`, `test/handlers/`, `test/providers/`, `test/exceptions/`, `test/cli/`
- CLI tests in `test/cli/commands/` — override `getProjectRoot()` and `getStubSearchPaths()` for temp dirs
- Use `group()` for logical grouping by feature/scenario
- Import from `package:magic_deeplink/src/...` (internal paths) in tests, not barrel — tests need granular access
- Assertions: `expect()`, `isA<T>()`, `throwsA()`, `isFalse`, `isTrue`, `isNull`, `isNotNull`
- Stream testing: listen to `manager.onLink`, trigger `handleUri()`, verify emission
- Provider tests: create `MagicApp.instance`, register provider, verify bindings with `app.make<T>('key')`
- Exception tests: verify `DeeplinkException` message, code, `toString()` output
