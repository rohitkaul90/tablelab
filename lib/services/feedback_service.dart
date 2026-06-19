import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_retry.dart';

/// Thrown when `submit-feedback` rejects a request with a non-2xx status
/// (e.g. 429 daily limit, 400 validation, 500 server). [message] is the
/// server's user-facing text when present. Network/transport errors are NOT
/// wrapped in this type — they propagate as-is so the UI can tell "server
/// rejected" from "couldn't reach the server".
class FeedbackException implements Exception {
  final int status;
  final String? message;
  const FeedbackException({required this.status, this.message});

  @override
  String toString() => 'FeedbackException($status): ${message ?? ''}';
}

/// Submits in-app user feedback to the `submit-feedback` Edge Function, which
/// stores it in the `feedback` table and notifies the #user-feedback Discord
/// channel. The webhook URL lives server-side (never in the client).
class FeedbackService {
  /// [client] is injectable for tests; production uses the global Supabase
  /// client, resolved lazily so the service can be constructed without an
  /// initialized Supabase instance (mirrors [AiService]).
  FeedbackService([SupabaseClient? client]) : _injected = client;

  final SupabaseClient? _injected;
  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  /// Sends one feedback item. [category] must be one of the server's accepted
  /// categories (bug/idea/praise/other). When [shareEmail] is true the server
  /// records the user's email for follow-up. Throws [FeedbackException] when the
  /// server rejects the request (carrying status + message); other failures
  /// (network) propagate as-is so the caller can distinguish them.
  Future<void> submit({
    required String category,
    required String message,
    int? rating,
    bool shareEmail = false,
  }) async {
    final appVersion = await _appVersion();
    try {
      await withSupabaseRetry(
        () => _client.functions.invoke(
          'submit-feedback',
          body: {
            'category': category,
            'message': message,
            if (rating != null) 'rating': rating,
            'shareEmail': shareEmail,
            if (appVersion != null) 'appVersion': appVersion,
            'platform': _platform(),
          },
        ),
      );
    } on FunctionException catch (e) {
      // invoke() throws on any non-2xx; the server's message lives in
      // details as {error: ...}. Surface it with the status so the UI can
      // tell limit (429) / validation (4xx) / server (5xx) apart.
      final details = e.details;
      final serverMsg =
          details is Map && details['error'] is String ? details['error'] as String : null;
      throw FeedbackException(status: e.status, message: serverMsg);
    }
  }

  Future<String?> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return null;
    }
  }

  String _platform() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name; // android | iOS | windows | …
  }
}
