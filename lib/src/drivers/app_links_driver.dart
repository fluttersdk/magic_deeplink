// Conditional export to select the right platform arm for `AppLinksDriver`.
//
// The stub is the default: it resolves only when neither guard below
// matches, which no real Flutter build target does. The web guard picks the
// `dart:js_interop` library rather than the legacy `dart:html` one, because
// the legacy library is absent under a wasm web compile; guarding on it
// there would fall through to the io guard and hand a browser the native
// driver instead. The io guard picks the native (Android/iOS/macOS/...) arm,
// the only one of the three allowed to import the `dart.library.io` platform
// library.
export 'app_links_driver_stub.dart'
    if (dart.library.js_interop) 'app_links_driver_web.dart'
    if (dart.library.io) 'app_links_driver_io.dart';
