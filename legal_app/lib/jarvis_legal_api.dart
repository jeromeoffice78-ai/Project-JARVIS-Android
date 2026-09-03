import 'dart:convert';

import 'package:http/http.dart' as http;

final class JarvisLegalApi {
  JarvisLegalApi({
    String? baseUrl,
    String? clientToken,
    http.Client? client,
  })  : _baseUrl = (baseUrl ?? const String.fromEnvironment('JARVIS_HTTP_BASE')).trim(),
        _clientToken = (clientToken ?? const String.fromEnvironment('JARVIS_CLIENT_TOKEN')).trim(),
        _client = client ?? http.Client();

  final String _baseUrl;
  final String _clientToken;
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

    final Uri uri = Uri.parse('$_baseUrl/v1/legal/query');
    final Map<String, String> headers = <String, String>{
      'content-type': 'application/json',
      if (_clientToken.isNotEmpty) 'authorization': 'Bearer $_clientToken',
    };

    final http.Response response = await _client
        .post(
          uri,
          headers: headers,
          body: jsonEncode(<String, dynamic>{
            'prompt': prompt,
            'role': role,
            if (matterId != null) 'matter_id': matterId,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('JARVIS legal backend returned HTTP ${response.statusCode}.');
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      final Object? answer = decoded['answer'] ?? decoded['response'] ?? decoded['text'];
      if (answer is String && answer.trim().isNotEmpty) {
        return answer.trim();
      }
    }
    throw StateError('JARVIS legal backend returned an invalid response.');
  }

  void close() => _client.close();
}
