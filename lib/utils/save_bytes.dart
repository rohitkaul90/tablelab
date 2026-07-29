/// Platform-conditional "save these bytes as a file" for the export screen.
///
/// `file_picker` 8.x has NO web `saveFile` implementation (it throws
/// `UnimplementedError` — the web download variant only exists from 9.x), so
/// on web we trigger a browser download directly instead of going through the
/// plugin. Same conditional-export pattern as `lib/equity/compute_compat.dart`.
///
/// The stub (non-web) variant throws — callers must gate on `kIsWeb`.
library;

export 'save_bytes_stub.dart' if (dart.library.js_interop) 'save_bytes_web.dart';
