import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

const Color _authBg = Color(0xFF05090D);
const Color _authPanel = Color(0xFF0A1218);
const Color _authPanel2 = Color(0xFF0E1B22);
const Color _authCyan = Color(0xFF38E8FF);
const Color _authGold = Color(0xFFFFC857);
const Color _authGreen = Color(0xFF62E6A7);
const Color _authMuted = Color(0xFF91A6B2);
const Color _authBorder = Color(0xFF183746);

final class ChairmanAuthSession {
  ChairmanAuthSession._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String tokenKey = 'jarvis_chairman_access_token';
  static const String expiresKey = 'jarvis_chairman_access_expires';
  static const String emailKey = 'jarvis_chairman_email';
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<String> token() async =>
      (await _storage.read(key: tokenKey) ?? '').trim();

  static Future<void> save({
    required String token,
    required String expiresAt,
    required String email,
  }) async {
    await _storage.write(key: tokenKey, value: token);
    await _storage.write(key: expiresKey, value: expiresAt);
    await _storage.write(key: emailKey, value: email);
    changes.value++;
  }

  static Future<void> clear() async {
    await _storage.delete(key: tokenKey);
    await _storage.delete(key: expiresKey);
    await _storage.delete(key: emailKey);
    changes.value++;
  }
}

class ChairmanAuthGate extends StatefulWidget {
  const ChairmanAuthGate({required this.child, super.key});

  final Widget child;

  @override
  State<ChairmanAuthGate> createState() => _ChairmanAuthGateState();
}

class _ChairmanAuthGateState extends State<ChairmanAuthGate> {
  static const String _baseUrl = String.fromEnvironment('JARVIS_HTTP_BASE');
  static const String _googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  final http.Client _client = http.Client();
  final GoogleSignIn _google = GoogleSignIn.instance;

  bool _checking = true;
  bool _authenticated = false;
  bool _submitting = false;
  bool _googleInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ChairmanAuthSession.changes.addListener(_onSessionChanged);
    _initialize();
  }

  @override
  void dispose() {
    ChairmanAuthSession.changes.removeListener(_onSessionChanged);
    _client.close();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    _restoreSession();
  }

  Future<void> _initialize() async {
    if (_baseUrl.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Secure JARVIS backend is not configured in this build.';
      });
      return;
    }

    if (_googleServerClientId.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Google Chairman authentication is not configured in this build.';
      });
      return;
    }

    try {
      await _google.initialize(serverClientId: _googleServerClientId.trim());
      _googleInitialized = true;
      await _restoreSession();
      if (!_authenticated) {
        final Future<GoogleSignInAccount?>? lightweight =
            _google.attemptLightweightAuthentication();
        final GoogleSignInAccount? account =
            lightweight == null ? null : await lightweight;
        if (account != null) {
          await _exchangeGoogleIdentity(account, interactive: false);
        }
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Unable to initialize Google sign-in: $error';
      });
    }
  }

  Future<void> _restoreSession() async {
    final String token = await ChairmanAuthSession.token();
    if (token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _authenticated = false;
      });
      return;
    }

    try {
      final http.Response response = await _client
          .get(
            Uri.parse('${_baseUrl.trim()}/v1/auth/session'),
            headers: <String, String>{'authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          _checking = false;
          _authenticated = true;
          _error = null;
        });
      } else {
        await ChairmanAuthSession.clear();
        if (!mounted) return;
        setState(() {
          _checking = false;
          _authenticated = false;
        });
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _authenticated = false;
        _error = 'Unable to verify the Chairman session. Check your connection.';
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_submitting) return;
    if (!_googleInitialized) {
      setState(() => _error = 'Google sign-in is not ready yet.');
      return;
    }
    if (!_google.supportsAuthenticate()) {
      setState(() => _error = 'Interactive Google sign-in is unavailable on this device.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final GoogleSignInAccount account = await _google.authenticate();
      await _exchangeGoogleIdentity(account, interactive: true);
    } on GoogleSignInException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Google sign-in failed: ${error.code.name}.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Secure Google sign-in failed: $error';
      });
    }
  }

  Future<void> _exchangeGoogleIdentity(
    GoogleSignInAccount account, {
    required bool interactive,
  }) async {
    final String idToken = account.authentication.idToken?.trim() ?? '';
    if (idToken.isEmpty) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _submitting = false;
        _error = 'Google did not return an identity token for this account.';
      });
      return;
    }

    try {
      final http.Response response = await _client
          .post(
            Uri.parse('${_baseUrl.trim()}/v1/auth/google'),
            headers: const <String, String>{'content-type': 'application/json'},
            body: jsonEncode(<String, String>{'id_token': idToken}),
          )
          .timeout(const Duration(seconds: 20));

      final Object? decoded = jsonDecode(response.body);
      final Map<String, dynamic> payload = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final String token = (payload['access_token'] as String? ?? '').trim();
        final String expiresAt = (payload['expires_at'] as String? ?? '').trim();
        final String email = (payload['email'] as String? ?? account.email).trim();
        final String role = (payload['role'] as String? ?? '').trim().toLowerCase();
        final bool exempt = payload['subscription_exempt'] == true;
        if (token.isEmpty || expiresAt.isEmpty || role != 'chairman' || !exempt) {
          throw const FormatException('Chairman authorization response was incomplete.');
        }
        await ChairmanAuthSession.save(
          token: token,
          expiresAt: expiresAt,
          email: email,
        );
        if (!mounted) return;
        setState(() {
          _authenticated = true;
          _checking = false;
          _submitting = false;
          _error = null;
        });
        return;
      }

      final String message = (payload['detail'] as String? ??
              payload['error'] as String? ??
              'This Google account is not authorized for Chairman access.')
          .trim();
      if (interactive) {
        await _google.signOut();
      }
      if (!mounted) return;
      setState(() {
        _checking = false;
        _submitting = false;
        _authenticated = false;
        _error = message;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _submitting = false;
        _authenticated = false;
        _error = 'Unable to establish the secure JARVIS session: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: _authBg,
        body: Center(child: CircularProgressIndicator(color: _authCyan)),
      );
    }
    if (_authenticated) return widget.child;

    return Scaffold(
      backgroundColor: _authBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _authPanel,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0x6638E8FF)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x2438E8FF),
                      blurRadius: 28,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Center(
                      child: CircleAvatar(
                        radius: 34,
                        backgroundColor: Color(0x1738E8FF),
                        child: Icon(Icons.balance_rounded, color: _authCyan, size: 34),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'JARVIS LEGAL ENTERPRISE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'CHAIRMAN SECURE ACCESS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _authCyan,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: _authPanel2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _authBorder),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(Icons.verified_user_outlined, color: _authGreen, size: 20),
                          SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'Use the approved Chairman Google account. Google verifies identity; JARVIS verifies Chairman authority and issues a secure session.',
                              style: TextStyle(color: _authMuted, fontSize: 11, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: const Color(0x18FF7272),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x55FF7272)),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFFFFB2B2)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _signInWithGoogle,
                      icon: _submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: const Text('CONTINUE WITH GOOGLE'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Chairman account: permanent owner access • subscription exempt',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _authGold,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
