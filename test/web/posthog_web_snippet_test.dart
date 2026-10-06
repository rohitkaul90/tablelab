import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/config/analytics_config.dart';

// On web, posthog_flutter only forwards Dart calls to `window.posthog`; the
// loader + init live in web/index.html, where the project key and host are a
// SECOND copy of lib/config/analytics_config.dart. Without the snippet every
// web analytics call throws and is dropped (zero web events were recorded from
// launch until this was added). These tests guard the snippet's presence, the
// key/host parity, and the privacy-relevant settings.
void main() {
  late String html;

  setUpAll(() {
    html = File('web/index.html').readAsStringSync();
  });

  test('loads posthog-js and initialises it before Flutter boots', () {
    final init = html.indexOf('posthog.init(');
    final bootstrap = html.indexOf('flutter_bootstrap.js');
    expect(html, contains('window.posthog=e'), reason: 'loader stub missing');
    expect(init, greaterThan(0), reason: 'posthog.init( missing');
    expect(bootstrap, greaterThan(init),
        reason: 'window.posthog must exist before the Flutter app starts');
  });

  test('key and host match analytics_config.dart', () {
    expect(html, contains("posthog.init('$posthogApiKey'"));
    expect(html, contains("api_host: '$posthogHost'"));
  });

  test('stores nothing on the device and strips URL query/hash', () {
    expect(html, contains("persistence: 'memory'"));
    expect(html, contains('before_send: window.tlSanitizePosthogEvent'));
    expect(html, contains(r'v.split(/[?#]/)[0]'));
    // The key filter decides WHICH properties get stripped; narrowing it
    // would let a URL-bearing property through untouched.
    expect(html, contains(r'/(url|referrer|href)$/i.test(k)'));
  });

  test('returning signed-in users are bootstrapped, not re-minted per load',
      () {
    expect(html, contains(r'/^sb-.+-auth-token$/.test(k)'));
    expect(
      html,
      contains('bootstrap: uid ? { distinctID: uid, isIdentifiedID: true } : {}'),
    );
  });

  test('only sends from the production host', () {
    expect(html, contains(r'/(^|\.)tablelab\.app$/.test(location.hostname)'));
    expect(html, contains('opt_out_capturing_by_default: !isProd'));
  });

  test('canvas-irrelevant capture features stay off', () {
    for (final setting in const [
      'autocapture: false',
      'capture_pageview: false',
      'disable_session_recording: true',
      'disable_surveys: true',
      'capture_exceptions: false',
      'advanced_disable_flags: true',
    ]) {
      expect(html, contains(setting));
    }
  });

  test('sends the app-open event the dashboards key on', () {
    expect(html, contains("posthog.capture('Application Opened'"));
  });
}
