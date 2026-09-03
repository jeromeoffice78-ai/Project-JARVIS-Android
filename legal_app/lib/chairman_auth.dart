import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  final TextEditingController _displayName =
      TextEditingController(text: 'Jerome Office');
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmPassword = TextEditingController();
  final http.Client _client = http.Client();

  bool _checking = true;
  bool _authenticated = false;
  bool _setupMode = false;
  bool _submitting = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    ChairmanAuthSession.changes.addListener(_onSessionChanged);
    _restoreSession();
  }

  @override
  void dispose() {
    ChairmanAuthSession.changes.removeListener(_onSessionChanged);
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _client.close();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    if (_baseUrl.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _authenticated = false;
        _error = 'Secure JARVIS backend is not configured in this build.';
      });
      return;
    }

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
            Uri.parse('${_baseUrl.trim()}/_api/v1/auth/mobile-session'),
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

  Future<void> _submit() async {
    if (_submitting) return;
    final String email = _email.text.trim();
    final String password = _password.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are required.');
      return;
    }
    if (_setupMode) {
      if (_displayName.text.trim().length < 2) {
        setState(() => _error = 'Chairman display name is required.');
        return;
      }
      if (password.length < 12) {
        setState(() => _error = 'Use at least 12 characters for the Chairman password.');
        return;
      }
      if (password != _confirmPassword.text) {
        setState(() => _error = 'The passwords do not match.');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final String route = _setupMode ? 'mobile-register' : 'mobile-login';
      final Map<String, Object> body = <String, Object>{
        'email': email,
        'password': password,
        if (_setupMode) 'displayName': _displayName.text.trim(),
      };
      final http.Response response = await _client
          .post(
            Uri.parse('${_baseUrl.trim()}/_api/v1/auth/$route'),
            headers: const <String, String>{'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      final Object? decoded = jsonDecode(response.body);
      final Map<String, dynamic> payload = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final String token = (payload['accessToken'] as String? ?? '').trim();
        final String expiresAt = (payload['expiresAt'] as String? ?? '').trim();
        if (token.isEmpty || expiresAt.isEmpty) {
          throw const FormatException('Authentication response was incomplete.');
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
          _password.clear();
          _confirmPassword.clear();
        });
        return;
      }

      final String message = (payload['error'] as String? ??
              payload['message'] as String? ??
              'Chairman authentication failed.')
          .trim();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = message;
        if (response.statusCode == 409) _setupMode = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Secure sign-in failed: $error';
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
                    Text(
                      _setupMode
                          ? 'INITIALIZE CHAIRMAN AUTHORITY'
                          : 'CHAIRMAN SECURE ACCESS',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _authCyan,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_setupMode) ...<Widget>[
                      _field(
                        controller: _displayName,
                        label: 'Chairman name',
                        icon: Icons.badge_outlined,
                      ),
                      const SizedBox(height: 10),
                    ],
                    _field(
                      controller: _email,
                      label: 'Chairman email',
                      icon: Icons.alternate_email_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    _field(
                      controller: _password,
                      label: 'Password',
                      icon: Icons.lock_outline_rounded,
                      obscureText: _hidePassword,
                      suffix: IconButton(
                        onPressed: () =>
                            setState(() => _hidePassword = !_hidePassword),
                        icon: Icon(
                          _hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    if (_setupMode) ...<Widget>[
                      const SizedBox(height: 10),
                      _field(
                        controller: _confirmPassword,
                        label: 'Confirm password',
                        icon: Icons.verified_user_outlined,
                        obscureText: _hidePassword,
                      ),
                    ],
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
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _setupMode
                                  ? Icons.admin_panel_settings_rounded
                                  : Icons.login_rounded,
                            ),
                      label: Text(
                        _setupMode ? 'CREATE CHAIRMAN ACCESS' : 'SIGN IN AS CHAIRMAN',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() {
                                _setupMode = !_setupMode;
                                _error = null;
                              }),
                      child: Text(
                        _setupMode
                            ? 'Already initialized? Sign in'
                            : 'First launch? Initialize Chairman access',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: _authPanel2,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: _authBorder),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(Icons.shield_outlined, color: _authGreen, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your password is verified by the hosted authentication service. The app stores only the encrypted session token in Android secure storage.',
                              style: TextStyle(color: _authMuted, fontSize: 10.5, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Chairman account: permanent owner access • subscription exempt',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _authGold, fontSize: 9.5, fontWeight: FontWeight.w800),
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

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: !obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        filled: true,
        fillColor: _authPanel2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onSubmitted: (_) => _submit(),
    );
  }
}
