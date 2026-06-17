// Pure-Dart VM build (CLI tools): run the callback inline. dart:ui — and thus
// package:flutter/foundation's compute() — is unavailable here. The eval baker
// is a batch job with no UI thread to keep responsive, so synchronous execution
// is fine. Signature mirrors Flutter's compute(). See compute_compat.dart.
Future<R> compute<Q, R>(
  R Function(Q) callback,
  Q message, {
  String? debugLabel,
}) async =>
    callback(message);
