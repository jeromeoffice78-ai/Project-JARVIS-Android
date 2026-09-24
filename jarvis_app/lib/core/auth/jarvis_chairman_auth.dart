import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

final class JarvisAuthSession {
  JarvisAuthSession._();

  static const FlutterSecureStorage _storage =
      FlutterSecureStorage();

  static const String _tokenKey =
      'jarvis_chairman_access_token';
  static const String _expiresKey =
      'jarvis_chairman_access_expires';
  static const String _emailKey =
      'jarvis_chairman_email';

  static String _currentToken = '';

  static String get currentToken =>
      _currentToken.trim();

  static Future<String> loadToken() async {
    _currentToken =
        (await _storage.read(key: _tokenKey) ?? '')
            .trim();
    return _currentToken;
  }

  static Future<void> save({
    required String token,
    required String expiresAt,
    required String email,
  }) async {
    _currentToken = token.trim();
    await _storage.write(
      key: _tokenKey,
      value: _currentToken,
    );
    await _storage.write(
      key: _expiresKey,
      value: expiresAt,
    );
    await _storage.write(
      key: _emailKey,
      value: email,
    );
  }

  static Future<void> clear() async {
    _currentToken = '';
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _expiresKey);
    await _storage.delete(key: _emailKey);
  }
}

class JarvisChairmanAuthGate
    extends StatefulWidget {
  const JarvisChairmanAuthGate({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<JarvisChairmanAuthGate> createState() =>
      _JarvisChairmanAuthGateState();
}

class _JarvisChairmanAuthGateState
    extends State<JarvisChairmanAuthGate> {
  static const String _baseUrl =
      String.fromEnvironment(
    'JARVIS_HTTP_BASE',
    defaultValue:
        'https://jarvis-legal-enterprise-api.onrender.com',
  );

  static const String _googleServerClientId =
      String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '498363735983-nka03bna11698m7o6ao0l7vnga8fb80e.apps.googleusercontent.com',
  );

  final http.Client _client = http.Client();

  late final GoogleSignIn _google =
      GoogleSignIn(
    scopes: const <String>[
      'email',
      'profile',
    ],
    serverClientId:
        _googleServerClientId,
  );

  bool _checking = true;
  bool _authenticated = false;
  bool _offlineMode = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _initialize() async {
    final String token =
        await JarvisAuthSession.loadToken();

    if (token.isNotEmpty &&
        await _verifySession(token)) {
      if (!mounted) {
        return;
      }
      setState(() {
        _checking = false;
        _authenticated = true;
        _error = null;
      });
      return;
    }

    try {
      final GoogleSignInAccount? account =
          await _google.signInSilently();

      if (account != null) {
        await _exchangeGoogleIdentity(
          account,
          interactive: false,
        );
        return;
      }
    } on Object {
      // Interactive sign-in remains available.
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _checking = false;
      _authenticated = false;
    });
  }

  Future<bool> _verifySession(
    String token,
  ) async {
    try {
      final http.Response response =
          await _client
              .get(
                Uri.parse(
                  '$_baseUrl/v1/auth/session',
                ),
                headers: <String, String>{
                  'authorization':
                      'Bearer $token',
                },
              )
              .timeout(
                const Duration(seconds: 20),
              );

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        return true;
      }

      await JarvisAuthSession.clear();
      return false;
    } on Object {
      return false;
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_submitting) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _google.signOut();

      final GoogleSignInAccount? account =
          await _google.signIn();

      if (account == null) {
        if (!mounted) {
          return;
        }
        setState(() {
          _submitting = false;
          _error =
              'Google sign-in was canceled.';
        });
        return;
      }

      await _exchangeGoogleIdentity(
        account,
        interactive: true,
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _submitting = false;
        _error =
            'Google sign-in failed: $error';
      });
    }
  }

  Future<void> _exchangeGoogleIdentity(
    GoogleSignInAccount account, {
    required bool interactive,
  }) async {
    final GoogleSignInAuthentication auth =
        await account.authentication;

    final String idToken =
        auth.idToken?.trim() ?? '';

    if (idToken.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _checking = false;
        _submitting = false;
        _error =
            'Google did not return an identity token.';
      });
      return;
    }

    try {
      final http.Response response =
          await _client
              .post(
                Uri.parse(
                  '$_baseUrl/v1/auth/google',
                ),
                headers:
                    const <String, String>{
                  'content-type':
                      'application/json',
                },
                body: jsonEncode(
                  <String, String>{
                    'id_token': idToken,
                  },
                ),
              )
              .timeout(
                const Duration(seconds: 30),
              );

      Object? decoded;
      try {
        decoded =
            jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }

      final Map<String, dynamic> payload =
          decoded is Map
              ? Map<String, dynamic>.from(
                  decoded,
                )
              : <String, dynamic>{};

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        final String token =
            payload['access_token']
                    ?.toString()
                    .trim() ??
                '';
        final String expiresAt =
            payload['expires_at']
                    ?.toString()
                    .trim() ??
                '';
        final String email =
            payload['email']
                    ?.toString()
                    .trim() ??
                account.email;

        if (token.isEmpty ||
            expiresAt.isEmpty) {
          throw const FormatException(
            'JARVIS authentication response was incomplete.',
          );
        }

        await JarvisAuthSession.save(
          token: token,
          expiresAt: expiresAt,
          email: email,
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _authenticated = true;
          _checking = false;
          _submitting = false;
          _offlineMode = false;
          _error = null;
        });
        return;
      }

      if (interactive) {
        await _google.signOut();
      }

      final String message =
          payload['detail']
                  ?.toString()
                  .trim() ??
              'This Google account is not authorized for Chairman access.';

      if (!mounted) {
        return;
      }

      setState(() {
        _checking = false;
        _submitting = false;
        _authenticated = false;
        _error = message;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _checking = false;
        _submitting = false;
        _authenticated = false;
        _error =
            'Unable to establish a secure JARVIS session: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF05090D),
        body: Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    if (_authenticated ||
        _offlineMode) {
      return widget.child;
    }

    return Scaffold(
      backgroundColor:
          const Color(0xFF05090D),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth: 520,
              ),
              child: Card(
                color:
                    const Color(0xFF0A1218),
                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    22,
                  ),
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.memory,
                        size: 58,
                        color:
                            Color(0xFF38E8FF),
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      const Text(
                        'JARVIS AI ASSISTANT',
                        textAlign:
                            TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight:
                              FontWeight.w900,
                          letterSpacing: 1.3,
                        ),
                      ),
                      const SizedBox(
                        height: 6,
                      ),
                      const Text(
                        'CHAIRMAN SECURE ACCESS',
                        style: TextStyle(
                          color:
                              Color(0xFF38E8FF),
                          fontSize: 11,
                          fontWeight:
                              FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(
                        height: 18,
                      ),
                      const Text(
                        'Sign in with the approved Chairman Google account to activate remote AI, voice, cloud-device and protected backend features.',
                        textAlign:
                            TextAlign.center,
                        style: TextStyle(
                          color:
                              Colors.white70,
                          height: 1.45,
                        ),
                      ),
                      if (_error != null) ...<
                          Widget>[
                        const SizedBox(
                          height: 14,
                        ),
                        Text(
                          _error!,
                          textAlign:
                              TextAlign.center,
                          style:
                              const TextStyle(
                            color:
                                Colors.amberAccent,
                          ),
                        ),
                      ],
                      const SizedBox(
                        height: 20,
                      ),
                      SizedBox(
                        width:
                            double.infinity,
                        child:
                            FilledButton.icon(
                          onPressed:
                              _submitting
                                  ? null
                                  : _signInWithGoogle,
                          icon: _submitting
                              ? const SizedBox.square(
                                  dimension:
                                      18,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth:
                                        2,
                                  ),
                                )
                              : const Icon(
                                  Icons.login,
                                ),
                          label: const Text(
                            'CONTINUE WITH GOOGLE',
                          ),
                        ),
                      ),
                      const SizedBox(
                        height: 10,
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _offlineMode =
                                true;
                          });
                        },
                        child: const Text(
                          'CONTINUE WITH LOCAL FEATURES',
                        ),
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
