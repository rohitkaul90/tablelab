import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/l10n.dart';
import '../../services/apple_sign_in.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isRegister = false;
  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _resetLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = context.l10n;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      if (_isRegister) {
        // Confirmation links redirect to an https page (works on every device
        // and email client — a browser cannot open the io.supabase.pokertracker://
        // custom scheme, which is what rendered a blank page). confirmed.html
        // shows a verified message and, on mobile, an "Open the app" deep link.
        final res = await client.auth.signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          emailRedirectTo: 'https://tablelab.app/confirmed.html',
        );
        if (res.session == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.loginConfirmationSent),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      } else {
        await client.auth.signInWithPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final l10n = context.l10n;
    final email = _emailCtrl.text.trim();
    String? target = email.contains('@') ? email : null;

    if (target == null) {
      // Ask for email in a dialog
      final ctrl = TextEditingController();
      target = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.loginResetPasswordTitle),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: l10n.loginEmailAddress,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(l10n.loginSendLink),
            ),
          ],
        ),
      );
    }

    if (target == null || target.isEmpty || !target.contains('@')) return;
    setState(() => _resetLoading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        target,
        redirectTo: 'https://tablelab.app',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.loginResetLinkSent(target))),
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _resetLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      const mobileRedirect = 'io.supabase.pokertracker://login-callback/';
      const webRedirect = 'https://tablelab.app/';
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? webRedirect : mobileRedirect,
      );
      // Web: browser redirects externally; AuthGate picks up the session on return.
      // Android: Chrome Custom Tab opens, redirects back via the deep-link scheme.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  /// App Store Review Guideline 4.8: an app offering Google login must also
  /// offer Sign in with Apple. Native flow — no browser round trip: Apple
  /// signs the SHA-256 of a nonce into the identity token and Supabase
  /// verifies it against the raw nonce (see apple_sign_in.dart).
  Future<void> _signInWithApple() async {
    final l10n = context.l10n; // captured before the first await
    setState(() {
      _appleLoading = true;
      _error = null;
    });
    try {
      final rawNonce = generateRawNonce();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256Hex(rawNonce),
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        debugPrint('Sign in with Apple: credential carried no identityToken');
        if (mounted) setState(() => _error = l10n.loginAppleFailed);
        return;
      }
      final auth = Supabase.instance.client.auth;
      await auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      // Store the refresh token server-side for revocation on account deletion.
      // Fire-and-forget: the user is already signed in at this point.
      unawaited(linkAppleAuthorization(
        Supabase.instance.client,
        credential.authorizationCode,
      ));
      // Apple sends the name ONLY on the very first authorization and never
      // inside the ID token, so persist it now or it is lost for good.
      // user_metadata.full_name is what ProfileService.googleName reads.
      final name = appleDisplayName(credential.givenName, credential.familyName);
      if (name != null) {
        try {
          await auth.updateUser(UserAttributes(data: {'full_name': name}));
        } catch (e) {
          debugPrint('Sign in with Apple: could not store full_name: $e');
        }
      }
      // AuthGate picks up the session from onAuthStateChange.
    } on SignInWithAppleAuthorizationException catch (e) {
      // `canceled` = the user dismissed the sheet. Everything else (incl.
      // `unknown`, which Apple uses for a device with no iCloud account)
      // carries a raw NSError string — log it, show a localized message.
      if (e.code == AuthorizationErrorCode.canceled) return;
      debugPrint('Sign in with Apple failed: ${e.code} ${e.message}');
      if (mounted) setState(() => _error = l10n.loginAppleFailed);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('Sign in with Apple failed: $e');
      if (mounted) setState(() => _error = l10n.loginAppleFailed);
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  /// iOS only: the native sheet needs the applesignin entitlement, and on
  /// Android/web Apple login would need a Services ID + web redirect that
  /// the project deliberately doesn't set up (Google + email cover them).
  /// `defaultTargetPlatform` honours the test override.
  bool get _showAppleSignIn =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                    Image.asset(
                      'assets/icon/app_icon.png',
                      width: 80,
                      height: 80,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'TableLab',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRegister
                          ? l10n.loginCreateYourAccount
                          : l10n.loginSignInToContinue,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.loginTagline,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.85),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Sign in with Apple (iOS only) ──────────────────────
                    if (_showAppleSignIn) ...[
                      SignInWithAppleButton(
                        key: const Key('sign_in_with_apple'),
                        text: _appleLoading
                            ? l10n.loginConnecting
                            : l10n.loginContinueWithApple,
                        height: 48,
                        style: theme.brightness == Brightness.dark
                            ? SignInWithAppleButtonStyle.white
                            : SignInWithAppleButtonStyle.black,
                        onPressed: (_loading || _googleLoading || _appleLoading)
                            ? null
                            : _signInWithApple,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Google sign-in ─────────────────────────────────────
                    OutlinedButton.icon(
                      onPressed:
                          (_loading || _googleLoading || _appleLoading) ? null : _signInWithGoogle,
                      icon: _googleLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const _GoogleLogo(),
                      label: Text(_googleLoading
                          ? l10n.loginConnecting
                          : l10n.loginContinueWithGoogle),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: BorderSide(
                            color: theme.colorScheme.outline.withAlpha(100)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Divider ────────────────────────────────────────────
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(l10n.loginOr,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline)),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Email / password ───────────────────────────────────
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.loginEmail,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return l10n.commonRequired;
                        }
                        if (!v.contains('@')) return l10n.loginEnterValidEmail;
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.loginPassword,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                      obscureText: true,
                      validator: (v) {
                        if (v == null || v.isEmpty) return l10n.commonRequired;
                        if (_isRegister && v.length < 6) {
                          return l10n.authAtLeast6Chars;
                        }
                        return null;
                      },
                    ),
                    if (!_isRegister) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: (_loading || _googleLoading || _appleLoading || _resetLoading)
                              ? null
                              : _forgotPassword,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: _resetLoading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  l10n.loginForgotPassword,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse('https://tablelab.app/about'),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: Text(l10n.loginLearnMore),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.primary,
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Wrap, not Row: translated labels ("Privacybeleid",
                    // "Politique de confidentialité") overflow a 360dp
                    // phone in a Row; a Wrap drops to a second line instead.
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _LegalLink(
                          label: l10n.loginPrivacyPolicy,
                          url: 'https://tablelab.app/privacy',
                        ),
                        Text(
                          '  ·  ',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        _LegalLink(
                          label: l10n.loginTerms,
                          url: 'https://tablelab.app/terms',
                        ),
                      ],
                    ),
                        ],
                      ),
                    ),
                  ),
                  // Pinned action — stays above the keyboard so Sign In is
                  // reachable while the user is typing email/password.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Error sits WITH the button in the pinned footer so a
                        // failed sign-in is visible even with the keyboard up
                        // (it used to live in the scroll body, above the fold).
                        if (_error != null) ...[
                          Text(
                            _error!,
                            style: TextStyle(color: theme.colorScheme.error),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                        ],
                        FilledButton(
                          onPressed:
                              (_loading || _googleLoading || _appleLoading) ? null : _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : Text(_isRegister
                                  ? l10n.loginCreateAccount
                                  : l10n.loginSignIn),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _isRegister = !_isRegister;
                            _error = null;
                          }),
                          child: Text(
                            _isRegister
                                ? l10n.loginHaveAccount
                                : l10n.loginNoAccount,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Muted, tappable legal link that opens the marketing site in the browser.
class _LegalLink extends StatelessWidget {
  final String label;
  final String url;

  const _LegalLink({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

// Simple Google "G" logo drawn with text since we have no asset
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) => const Text(
        'G',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF4285F4),
        ),
      );
}
