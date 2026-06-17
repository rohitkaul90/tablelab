// `compute` that works both in the Flutter app and in pure-Dart CLI tools.
//
// The equity engine offloads its Monte-Carlo / range build to a background
// isolate via Flutter's `compute()`. But `package:flutter/foundation` pulls in
// `dart:ui`, so importing it makes the equity engine un-runnable from a plain
// `dart run` — which the eval harness's Stage-1 baker (tool/eval/) needs.
//
// Conditional import: when `dart.library.ui` is available (the Flutter app, on
// BOTH mobile and web) we re-export Flutter's real `compute`; otherwise (the
// pure-Dart VM) we use a synchronous inline stand-in. The app's behavior is
// unchanged on every platform it ships to; only CLI tooling takes the shim.
export '_compute_vm.dart' if (dart.library.ui) '_compute_flutter.dart';
