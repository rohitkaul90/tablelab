import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_retry.dart';

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

  static const categories = ['bug', 'idea', 'praise', 'other'];

  /// Sends one feedback item. [category] must be one of [categories].
  /// When [shareEmail] is true the server records the user's email for
  /// follow-up. Throws on failure (rate limit, network, server error) so the
  /// caller can surface a message.
  Future<void> submit({
    required String category,
    required String message,
    int? rating,
    bool shareEmail = false,
  }) async {
    final appVersion = await _appVersion();
    final res = await withSupabaseRetry(
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

    final data = res.data;
    if (data is Map && data.containsKey('error')) {
      throw Exception(data['error']);
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
