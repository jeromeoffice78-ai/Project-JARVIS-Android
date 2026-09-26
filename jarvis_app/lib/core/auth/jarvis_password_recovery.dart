import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// In-app recovery: request a Supabase Auth email instead of opening the
/// Supabase Edge Function URL, which browsers render as plain text.
class JarvisPasswordRecoveryPage extends StatefulWidget {
  const JarvisPasswordRecoveryPage({super.key});

  @override
  State<JarvisPasswordRecoveryPage> createState() =>
      _JarvisPasswordRecoveryPageState();
}

class _JarvisPasswordRecoveryPageState
    extends State<JarvisPasswordRecoveryPage> {
  static const String _recoverEndpoint =
      'https://idpneeyysraraznqmiio.supabase.co/auth/v1/recover';
  static const String _publishableKey =
      'sb_publishable_u1kIRdIQj2I3Tly5Trv0OQ_i-S7JnAw';

  final TextEditingController _emailController = TextEditingController();
  final http.Client _client = http.Client();
  bool _sending = false;
  bool _requested = false;
  String? _message;

  @override
  void dispose() {
    _client.close();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    if (_sending) return;
    final String email = _emailController.text.trim();
    final RegExp emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailPattern.hasMatch(email)) {
      setState(() => _message = 'Enter your Jarvis account email address.');
      return;
    }
    setState(() {
      _sending = true;
      _requested = false;
      _message = null;
    });
    try {
      final http.Response response = await _client
          .post(
            Uri.parse(_recoverEndpoint),
            headers: const <String, String>{
              'content-type': 'application/json',
              'apikey': _publishableKey,
            },
            body: jsonEncode(<String, String>{'email': email}),
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() {
        _sending = false;
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _requested = true;
          _message =
              'If this email has a Jarvis account, a password-reset link '
              'has been requested. Check your Gmail inbox and spam. '
              'This process sends a LINK, not a six-digit code.';
        } else if (response.statusCode == 429) {
          _message =
              'Email requests are temporarily limited. Wait at least '
              'one minute before requesting another link.';
        } else {
          _message =
              'We could not request a password-reset email right now. '
              'Try again shortly.';
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _message =
            'Could not contact Jarvis account recovery. '
            'Check your Internet connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05090D),
      appBar: AppBar(
        title: const Text('Reset Jarvis Password'),
        backgroundColor: const Color(0xFF0A1218),
        foregroundColor: Colors.white,
      ),
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
                        Icons.lock_reset_rounded,
                        size: 52,
                        color: Color(0xFF38E8FF),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'RESET MY PASSWORD',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Enter the email you use for Jarvis. '
                        'We will request a secure password-recovery link. '
                        'You will not receive a numerical code.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: _emailController,
                        enabled: !_sending,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const <String>[AutofillHints.email],
                        autocorrect: false,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Jarvis account email',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _sendResetLink(),
                      ),
                      const SizedBox(height: 15),
                      FilledButton.icon(
                        onPressed: _sending ? null : _sendResetLink,
                        icon: _sending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.mark_email_unread_outlined),
                        label: const Text('SEND RESET LINK'),
                      ),
                      if (_message != null) ...<Widget>[
                        const SizedBox(height: 16),
                        SelectableText(
                          _message!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _requested
                                ? Colors.lightGreenAccent
                                : Colors.amberAccent,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Text(
                        'For Google sign-in, continue using your Google '
                        'account. Resetting a Jarvis email password does '
                        'not change your Google password.',
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
