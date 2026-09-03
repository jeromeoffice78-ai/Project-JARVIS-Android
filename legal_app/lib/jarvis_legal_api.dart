import 'dart:convert';

import 'package:http/http.dart' as http;

import 'chairman_auth.dart';

final class JarvisLegalApi {
  JarvisLegalApi({
    String? baseUrl,
    String? clientToken,
    http.Client? client,
  })  : _baseUrl =
            (baseUrl ?? const String.fromEnvironment('JARVIS_HTTP_BASE')).trim(),
        _fallbackToken =
            (clientToken ?? const String.fromEnvironment('JARVIS_CLIENT_TOKEN'))
                .trim(),
        _client = client ?? http.Client();

  final String _baseUrl;
  final String _fallbackToken;
  final http.Client _client;

  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<String> ask({
    required String prompt,
    required String role,
    String? matterId,
  }) async {
    if (!isConfigured) {
      throw StateError('JARVIS backend is not configured for this build.');
    }

    final String storedToken = await ChairmanAuthSession.token();
    final String token = storedToken.isNotEmpty ? storedToken : _fallbackToken;
    if (token.isEmpty) {
      throw StateError('Chairman authentication is required.');
    }

    final Uri uri = Uri.parse('$_baseUrl/_api/v1/legal/query');
    final http.Response response = await _client
        .post(
          uri,
          headers: <String, String>{
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode(<String, dynamic>{
            'prompt': prompt,
            'role': role,
            if (matterId != null) 'matter_id': matterId,
          }),
        )
        .timeout(const Duration(seconds: 75));

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      await ChairmanAuthSession.clear();
      final String detail = decoded is Map<String, dynamic>
          ? (decoded['error'] as String? ?? 'Chairman session expired.')
          : 'Chairman session expired.';
      throw StateError(detail);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String detail = decoded is Map<String, dynamic>
          ? (decoded['error'] as String? ??
              'JARVIS legal backend returned HTTP ${response.statusCode}.')
          : 'JARVIS legal backend returned HTTP ${response.statusCode}.';
      throw StateError(detail);
    }

    if (decoded is Map<String, dynamic>) {
      final Object? answer =
          decoded['answer'] ?? decoded['response'] ?? decoded['text'];
      if (answer is String && answer.trim().isNotEmpty) {
        return answer.trim();
      }
    }
    throw StateError('JARVIS legal backend returned an invalid response.');
  }

  void close() => _client.close();
}
