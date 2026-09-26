import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'jarvis_chairman_auth.dart';

/// Full JARVIS owner app: login is required on every new installation.
/// New signups receive Supabase's email confirmation; existing owners use
/// Sign In or Forgot Password instead of creating a duplicate account.
class JarvisPasswordAccountGate extends StatefulWidget {
  const JarvisPasswordAccountGate({
    required this.child,
    this.client,
    super.key,
  });

  final Widget child;
  final http.Client? client;

  @override
  State<JarvisPasswordAccountGate> createState() =>
      _JarvisPasswordAccountGateState();
}

enum _AccountMode { signIn, createAccount, forgotPassword, setNewPassword }

class _JarvisPasswordAccountGateState
    extends State<JarvisPasswordAccountGate> {
  static const String _supabase =
      'https://idpneeyysraraznqmiio.supabase.co';
  static const String _publicKey =
      'sb_publishable_u1kIRdIQj2I3Tly5Trv0OQ_i-S7JnAw';
  static const String _ownerEmail = String.fromEnvironment(
    'JARVIS_OWNER_EMAIL',
    defaultValue: 'jeromeoffice78@gmail.com',
  );
  static const String _backend = String.fromEnvironment(
    'JARVIS_HTTP_BASE',
    defaultValue: 'https://jarvis-legal-enterprise-api.onrender.com',
  );

  late final http.Client _http = widget.client ?? http.Client();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _recoveryLink = TextEditingController();

  _AccountMode _mode = _AccountMode.signIn;
  bool _checking = true;
  bool _authenticated = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    JarvisAuthSession.signInRequests.addListener(_onAccountAction);
    _restore();
  }

  @override
  void dispose() {
    JarvisAuthSession.signInRequests.removeListener(_onAccountAction);
    if (widget.client == null) _http.close();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _recoveryLink.dispose();
    super.dispose();
  }

  void _onAccountAction() {
    if (!mounted || _busy) return;
    if (_authenticated) {
      _showAccountOptions();
    } else {
      setState(() => _mode = _AccountMode.signIn);
    }
  }

  Future<void> _showAccountOptions() async {
    final bool? signOut = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Jarvis owner account'),
        content: const Text(
          'This device is signed in. Sign out to require your '
          'email and password the next time you open Jarvis.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('SIGN OUT'),
          ),
        ],
      ),
    );
    if (signOut != true || !mounted) return;
    await JarvisAuthSession.clear();
    if (!mounted) return;
    setState(() {
      _authenticated = false;
      _mode = _AccountMode.signIn;
      _password.clear();
      _confirm.clear();
      _notice = null;
      _error = null;
    });
  }

  Future<void> _restore() async {
    try {
      final String token = await JarvisAuthSession.loadToken()
          .timeout(const Duration(seconds: 10));
      if (token.isNotEmpty) {
        final http.Response response = await _http.get(
          Uri.parse(_backend + '/v1/auth/session'),
          headers: <String, String>{'authorization': 'Bearer ' + token},
        ).timeout(const Duration(seconds: 16));
        if (response.statusCode == 200) {
          if (!mounted) return;
          setState(() {
            _authenticated = true;
            _checking = false;
          });
          return;
        }
      }
      await JarvisAuthSession.clear();
    } on Object {
      // No valid stored session: ask the owner to sign in.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Map<String, String> get _apiHeaders => const <String, String>{
        'content-type': 'application/json',
        'apikey': _publicKey,
      };

  bool _validateEmail() {
    final String value = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      setState(() => _error = 'Enter a valid email address.');
      return false;
    }
    // This signed owner build never grants Chairman privileges to an
    // unapproved address; the backend enforces this independently.
    if (value != _ownerEmail.toLowerCase()) {
      setState(() => _error =
          'This owner edition requires the registered owner email. '
          'Use the approved Jarvis owner account.');
      return false;
    }
    return true;
  }

  String? _passwordError(String value) {
    if (value.length < 12) {
      return 'Use at least 12 characters.';
    }
    if (!RegExp(r'[a-z]').hasMatch(value) ||
        !RegExp(r'[A-Z]').hasMatch(value) ||
        !RegExp(r'[0-9]').hasMatch(value) ||
        !RegExp(r'[^a-zA-Z0-9]').hasMatch(value)) {
      return 'Use uppercase, lowercase, a number and a symbol.';
    }
    return null;
  }

  void _setMode(_AccountMode next) {
    if (_busy) return;
    setState(() {
      _mode = next;
      _error = null;
      _notice = null;
      _password.clear();
      _confirm.clear();
      _recoveryLink.clear();
    });
  }

  Future<void> _createAccount() async {
    if (!_validateEmail()) return;
    final String? problem = _passwordError(_password.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final http.Response response = await _http.post(
        Uri.parse(_supabase + '/auth/v1/signup'),
        headers: _apiHeaders,
        body: jsonEncode(<String, String>{
          'email': _email.text.trim().toLowerCase(),
          'password': _password.text,
        }),
      ).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() {
          _mode = _AccountMode.signIn;
          _notice = 'If this account is new, check your email and confirm '
              'your address, then sign in. If this address already has a '
              'Jarvis account, choose Forgot Password to set a password. '
              'No duplicate owner account is created.';
          _password.clear();
          _confirm.clear();
        });
      } else if (response.statusCode == 429) {
        setState(() => _error =
            'Too many email requests. Wait before trying again.');
      } else {
        setState(() => _error =
            'Account setup could not finish. If your owner account '
            'already exists, use Forgot Password.');
      }
    } on Object {
      if (mounted) {
        setState(() => _error =
            'Could not reach account registration. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    if (!_validateEmail()) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final http.Response login = await _http.post(
        Uri.parse(_supabase + '/auth/v1/token?grant_type=password'),
        headers: _apiHeaders,
        body: jsonEncode(<String, String>{
          'email': _email.text.trim().toLowerCase(),
          'password': _password.text,
        }),
      ).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (login.statusCode == 429) {
        setState(() => _error =
            'Too many attempts. Wait before trying again.');
        return;
      }
      if (login.statusCode != 200) {
        setState(() => _error =
            'Unable to sign in. Check your password and confirm your email. '
            'If you registered before, use Forgot Password.');
        return;
      }
      final Object? decoded = jsonDecode(login.body);
      final String supabaseToken = decoded is Map
          ? (decoded['access_token']?.toString() ?? '')
          : '';
      if (supabaseToken.isEmpty) {
        throw const FormatException('Missing secure session');
      }
      // Verify at the JARVIS backend: only the verified owner receives
      // Chairman access. Never share raw passwords with the JARVIS API.
      final http.Response owner = await _http.post(
        Uri.parse(_backend + '/v1/auth/password'),
        headers: const <String, String>{'content-type': 'application/json'},
        body: jsonEncode(<String, String>{
          'supabase_access_token': supabaseToken,
        }),
      ).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (owner.statusCode != 200) {
        setState(() => _error = owner.statusCode == 403
            ? 'Your email must be verified and approved for owner access.'
            : 'Jarvis could not verify your owner account. '
                'Please try again shortly.');
        return;
      }
      final Object? response = jsonDecode(owner.body);
      if (response is! Map) {
        throw const FormatException('Invalid session');
      }
      final String token = response['access_token']?.toString() ?? '';
      final String expires = response['expires_at']?.toString() ?? '';
      final String email = response['email']?.toString() ?? '';
      if (token.isEmpty || expires.isEmpty || email.isEmpty) {
        throw const FormatException('Incomplete secure session');
      }
      await JarvisAuthSession.save(
        token: token, expiresAt: expires, email: email,
      );
      _password.clear();
      _confirm.clear();
      if (!mounted) return;
      setState(() {
        _authenticated = true;
        _error = null;
      });
    } on Object {
      if (mounted) {
        setState(() => _error =
            'Sign-in is unavailable right now. Check your connection '
            'and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestRecovery() async {
    if (!_validateEmail()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final http.Response response = await _http.post(
        Uri.parse(_supabase + '/auth/v1/recover'),
        headers: _apiHeaders,
        body: jsonEncode(<String, String>{
          'email': _email.text.trim().toLowerCase(),
        }),
      ).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 204) {
        setState(() {
          _mode = _AccountMode.setNewPassword;
          _notice = 'Check your email for a recovery link. '
              'Copy the complete link WITHOUT OPENING IT and paste it here. '
              'This email contains a link, not a numeric code.';
          _password.clear();
          _confirm.clear();
        });
      } else if (response.statusCode == 429) {
        setState(() => _error =
            'Too many requests. Wait before requesting another link.');
      } else {
        setState(() => _error =
            'Password recovery is unavailable. Try again later.');
      }
    } on Object {
      if (mounted) {
        setState(() => _error = 'Could not contact password recovery.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updatePassword() async {
    final String? problem = _passwordError(_password.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    final Uri? link = Uri.tryParse(_recoveryLink.text.trim());
    if (link == null ||
        link.scheme != 'https' ||
        link.host != Uri.parse(_supabase).host ||
        link.path != '/auth/v1/verify' ||
        link.queryParameters['type'] != 'recovery') {
      setState(() => _error =
          'Paste the full, unused Jarvis password-recovery link.');
      return;
    }
    final String hash = link.queryParameters['token_hash'] ??
        link.queryParameters['token'] ?? '';
    if (!RegExp(r'^[A-Za-z0-9_-]{30,300}$').hasMatch(hash)) {
      setState(() => _error = 'This recovery link is incomplete.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final http.Response verification = await _http.post(
        Uri.parse(_supabase + '/auth/v1/verify'),
        headers: _apiHeaders,
        body: jsonEncode(<String, String>{
          'token_hash': hash,
          'type': 'recovery',
        }),
      ).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (verification.statusCode != 200) {
        setState(() => _error =
            'That link has expired or was already used. '
            'Request a new recovery email.');
        return;
      }
      final Object? proof = jsonDecode(verification.body);
      final String accessToken =
          proof is Map ? (proof['access_token']?.toString() ?? '') : '';
      if (accessToken.isEmpty) {
        throw const FormatException('Missing recovery session');
      }
      final http.Response update = await _http.put(
        Uri.parse(_supabase + '/auth/v1/user'),
        headers: <String, String>{
          ..._apiHeaders,
          'authorization': 'Bearer ' + accessToken,
        },
        body: jsonEncode(<String, String>{'password': _password.text}),
      ).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (update.statusCode != 200) {
        setState(() => _error =
            'Password update failed. Request another recovery email.');
        return;
      }
      setState(() {
        _mode = _AccountMode.signIn;
        _password.clear();
        _confirm.clear();
        _recoveryLink.clear();
        _notice = 'Your password was changed. Sign in with your email '
            'and new password.';
      });
    } on Object {
      if (mounted) {
        setState(() => _error =
            'Password recovery could not complete. Request a fresh link.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF05090D),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_authenticated) return widget.child;

    final bool creating = _mode == _AccountMode.createAccount;
    final bool forgot = _mode == _AccountMode.forgotPassword;
    final bool resetting = _mode == _AccountMode.setNewPassword;
    final String heading = creating
        ? 'CREATE YOUR JARVIS ACCOUNT'
        : forgot || resetting
            ? 'RESET JARVIS PASSWORD'
            : 'SIGN IN TO JARVIS';
    return Scaffold(
      backgroundColor: const Color(0xFF05090D),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                color: const Color(0xFF0A1218),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Icon(
                        Icons.memory, size: 54, color: Color(0xFF38E8FF),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        heading,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 21,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'JARVIS AI ASSISTANT · OWNER EDITION',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF38E8FF), fontSize: 11),
                      ),
                      const SizedBox(height: 16),
                      if (_notice != null) ...<Widget>[
                        Text(
                          _notice!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.lightGreenAccent),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_error != null) ...<Widget>[
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.amberAccent),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (!resetting)
                        TextField(
                          controller: _email,
                          enabled: !_busy,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const <String>[AutofillHints.email],
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            labelStyle: TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      if (creating || _mode == _AccountMode.signIn || resetting)
                        ...<Widget>[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            enabled: !_busy,
                            obscureText: _hidePassword,
                            style: const TextStyle(color: Colors.white),
                            autofillHints: <String>[
                              creating || resetting
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            decoration: InputDecoration(
                              labelText: resetting ? 'New password' : 'Password',
                              labelStyle: const TextStyle(color: Colors.white70),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword,
                                ),
                                icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),
                        ],
                      if (creating || resetting) ...<Widget>[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirm,
                          enabled: !_busy,
                          obscureText: _hidePassword,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            labelStyle: TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 7),
                        const Text(
                          '12+ characters, uppercase, lowercase, number, symbol.',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                      if (resetting) ...<Widget>[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _recoveryLink,
                          enabled: !_busy,
                          minLines: 2,
                          maxLines: 4,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Paste unused email recovery link',
                            labelStyle: TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : creating
                                ? _createAccount
                                : forgot
                                    ? _requestRecovery
                                    : resetting
                                        ? _updatePassword
                                        : _signIn,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.lock_outline),
                        label: Text(
                          creating
                              ? 'CREATE ACCOUNT'
                              : forgot
                                  ? 'SEND RECOVERY EMAIL'
                                  : resetting
                                      ? 'SET NEW PASSWORD'
                                      : 'SIGN IN',
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_mode == _AccountMode.signIn)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _setMode(_AccountMode.createAccount),
                          child: const Text('FIRST TIME? CREATE ACCOUNT'),
                        ),
                      if (_mode == _AccountMode.signIn)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _setMode(_AccountMode.forgotPassword),
                          child: const Text('FORGOT PASSWORD?'),
                        ),
                      if (_mode != _AccountMode.signIn)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _setMode(_AccountMode.signIn),
                          child: const Text('BACK TO SIGN IN'),
                        ),
                      const SizedBox(height: 6),
                      const Text(
                        'The owner edition accepts the registered owner email. '
                        'A verified account is required for remote AI, memory '
                        'and connected devices.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
