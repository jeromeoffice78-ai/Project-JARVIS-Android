import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/jarvis_config.dart';
import '../../features/people/person_profile.dart';

class JarvisFrontierResult {
  const JarvisFrontierResult({
    required this.answer,
    required this.model,
    required this.mode,
    required this.sources,
  });

  final String answer;
  final String model;
  final String mode;
  final List<Map<String, String>> sources;
}

class JarvisGeneratedImage {
  const JarvisGeneratedImage({
    required this.base64,
    required this.model,
  });

  final String base64;
  final String model;
}

class JarvisApiService {
  JarvisApiService({
    required JarvisConfig config,
    http.Client? client,
  })  : _config = config,
        _client = client ?? http.Client();

  final JarvisConfig _config;
  final http.Client _client;

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        if (_config.clientToken.isNotEmpty)
          'Authorization': 'Bearer ${_config.clientToken}',
      };

  Future<Map<String, dynamic>> health() async {
    final response = await _client.get(
      Uri.parse('${_config.httpBaseUrl}/health'),
    );

    if (response.statusCode != 200) {
      throw StateError('Health check failed: ${response.statusCode}');
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Invalid health response.');
    }

    return Map<String, dynamic>.from(decoded);
  }

  Future<String> createRealtimeClientSecret() async {
    final response = await _client.post(
      Uri.parse(
        '${_config.httpBaseUrl}/v1/realtime/client-secret',
      ),
      headers: _headers,
    );

    final Object? decoded = jsonDecode(response.body);
    if (response.statusCode != 200) {
      final String detail = decoded is Map
          ? decoded['detail']?.toString() ??
              'Realtime voice credential request failed.'
          : 'Realtime voice credential request failed.';
      throw StateError(
        'Realtime voice setup failed: $detail',
      );
    }

    if (decoded is! Map) {
      throw const FormatException(
        'Invalid Realtime credential response.',
      );
    }

    final String secret =
        decoded['value']?.toString() ?? '';

    if (secret.isEmpty) {
      throw const FormatException(
        'Realtime credential response contained no client secret.',
      );
    }

    return secret;
  }


  Future<JarvisFrontierResult> frontierQuery({
    required String prompt,
    required String mode,
    String? imageBase64,
  }) async {
    final response = await _client.post(
      Uri.parse(
        '${_config.httpBaseUrl}/v1/frontier/query',
      ),
      headers: _headers,
      body: jsonEncode(<String, dynamic>{
        'prompt': prompt,
        'mode': mode,
        if (imageBase64 != null &&
            imageBase64.isNotEmpty)
          'image_base64': imageBase64,
      }),
    );

    final Object? decoded = jsonDecode(response.body);
    if (response.statusCode != 200) {
      final String detail = decoded is Map
          ? decoded['detail']?.toString() ??
              'Frontier request failed.'
          : 'Frontier request failed.';
      throw StateError(
        'Frontier request failed: $detail',
      );
    }

    if (decoded is! Map) {
      throw const FormatException(
        'Invalid frontier response.',
      );
    }

    final Map<String, dynamic> data =
        Map<String, dynamic>.from(decoded);

    final Object? rawSources = data['sources'];
    final List<Map<String, String>> sources =
        rawSources is List
            ? rawSources
                .whereType<Map>()
                .map(
                  (Map raw) =>
                      <String, String>{
                    'title':
                        raw['title']
                                ?.toString() ??
                            '',
                    'url':
                        raw['url']?.toString() ??
                            '',
                  },
                )
                .where(
                  (Map<String, String> item) =>
                      item['url']!.isNotEmpty,
                )
                .toList(growable: false)
            : const <Map<String, String>>[];

    return JarvisFrontierResult(
      answer: data['answer']?.toString() ?? '',
      model: data['model']?.toString() ?? '',
      mode: data['mode']?.toString() ?? mode,
      sources: sources,
    );
  }

  Future<JarvisFrontierResult> analyzeFile({
    required List<int> bytes,
    required String filename,
    required String prompt,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        '${_config.httpBaseUrl}/v1/frontier/file',
      ),
    );

    if (_config.clientToken.isNotEmpty) {
      request.headers['Authorization'] =
          'Bearer ${_config.clientToken}';
    }

    request.fields['prompt'] = prompt;
    request.files.add(
      http.MultipartFile.fromBytes(
        'document',
        bytes,
        filename: filename,
      ),
    );

    final streamed = await _client.send(request);
    final String body =
        await streamed.stream.bytesToString();

    final Object? decoded = jsonDecode(body);
    if (streamed.statusCode != 200) {
      final String detail = decoded is Map
          ? decoded['detail']?.toString() ??
              'Document analysis failed.'
          : 'Document analysis failed.';
      throw StateError(
        'Document analysis failed: $detail',
      );
    }

    if (decoded is! Map) {
      throw const FormatException(
        'Invalid document analysis response.',
      );
    }

    final Map<String, dynamic> data =
        Map<String, dynamic>.from(decoded);

    return JarvisFrontierResult(
      answer: data['answer']?.toString() ?? '',
      model: data['model']?.toString() ?? '',
      mode: data['mode']?.toString() ?? 'file',
      sources: const <Map<String, String>>[],
    );
  }


  Future<JarvisGeneratedImage> generateImage(
    String prompt,
  ) async {
    final response = await _client.post(
      Uri.parse(
        '${_config.httpBaseUrl}/v1/frontier/image',
      ),
      headers: _headers,
      body: jsonEncode(<String, dynamic>{
        'prompt': prompt,
      }),
    );

    final Object? decoded = jsonDecode(response.body);
    if (response.statusCode != 200) {
      final String detail = decoded is Map
          ? decoded['detail']?.toString() ??
              'Image generation failed.'
          : 'Image generation failed.';
      throw StateError(
        'Image generation failed: $detail',
      );
    }

    if (decoded is! Map) {
      throw const FormatException(
        'Invalid image generation response.',
      );
    }

    final Map<String, dynamic> data =
        Map<String, dynamic>.from(decoded);

    final String base64 =
        data['image_base64']?.toString() ?? '';
    if (base64.isEmpty) {
      throw const FormatException(
        'Image generation returned no image.',
      );
    }

    return JarvisGeneratedImage(
      base64: base64,
      model: data['model']?.toString() ?? '',
    );
  }


  Future<String> saveMemory({
    required String text,
    String kind = 'fact',
    double importance = 0.5,
  }) async {
    final response = await _client.post(
      Uri.parse('${_config.httpBaseUrl}/memory'),
      headers: _headers,
      body: jsonEncode(<String, dynamic>{
        'text': text,
        'kind': kind,
        'importance': importance,
      }),
    );

    if (response.statusCode != 200) {
      throw StateError('Memory save failed: ${response.statusCode}');
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Invalid memory save response.');
    }

    final Map<String, dynamic> data =
        Map<String, dynamic>.from(decoded);

    return data['memory_id']?.toString() ?? '';
  }

  Future<String> queryMemory(String query) async {
    final uri = Uri.parse('${_config.httpBaseUrl}/memory/context').replace(
      queryParameters: <String, String>{'q': query},
    );

    final response = await _client.get(uri, headers: _headers);

    if (response.statusCode != 200) {
      throw StateError('Memory query failed: ${response.statusCode}');
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Invalid memory response.');
    }

    final Map<String, dynamic> data =
        Map<String, dynamic>.from(decoded);

    return data['context']?.toString() ?? '';
  }


  Future<void> uploadVisionFrame({
    required List<int> bytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${_config.httpBaseUrl}/vision/frame'),
    );

    if (_config.clientToken.isNotEmpty) {
      request.headers['Authorization'] =
          'Bearer ${_config.clientToken}';
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'frame',
        bytes,
        filename: filename,
      ),
    );

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw StateError(
        'Vision upload failed: ${response.statusCode}',
      );
    }

    final body = await response.stream.bytesToString();
    final Object? decoded = jsonDecode(body);

    if (decoded is! Map) {
      throw const FormatException(
        'Invalid vision upload response.',
      );
    }

    final Map<String, dynamic> data =
        Map<String, dynamic>.from(decoded);

    if (data['status'] != 'accepted') {
      throw StateError(
        'Vision frame rejected: ${data['reason'] ?? 'unknown'}',
      );
    }
  }

  Future<void> clearVisionFrame() async {
    final response = await _client.delete(
      Uri.parse('${_config.httpBaseUrl}/vision/frame'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Vision clear failed: ${response.statusCode}',
      );
    }
  }


  Future<List<PersonProfile>> listPeople() async {
    final response = await _client.get(
      Uri.parse('${_config.httpBaseUrl}/people'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw StateError(
        'People lookup failed: ${response.statusCode}',
      );
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Invalid people response.');
    }

    final Object? rawPeople = decoded['people'];
    if (rawPeople is! List) {
      return const <PersonProfile>[];
    }

    return rawPeople
        .whereType<Map>()
        .map(
          (Map raw) => PersonProfile.fromJson(
            Map<String, dynamic>.from(raw),
          ),
        )
        .toList(growable: false);
  }

  Future<PersonProfile> createPerson({
    required String displayName,
    String relationship = '',
    String notes = '',
  }) async {
    final response = await _client.post(
      Uri.parse('${_config.httpBaseUrl}/people'),
      headers: _headers,
      body: jsonEncode(<String, dynamic>{
        'display_name': displayName,
        'relationship': relationship,
        'notes': notes,
      }),
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Create person failed: ${response.statusCode}',
      );
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['person'] is! Map) {
      throw const FormatException(
        'Invalid create-person response.',
      );
    }

    return PersonProfile.fromJson(
      Map<String, dynamic>.from(
        decoded['person'] as Map,
      ),
    );
  }

  Future<void> confirmPersonPresent(
    String personId,
  ) async {
    final response = await _client.post(
      Uri.parse(
        '${_config.httpBaseUrl}/people/$personId/present',
      ),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Confirm person failed: ${response.statusCode}',
      );
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map ||
        decoded['status']?.toString() != 'confirmed') {
      throw StateError(
        'The person profile could not be confirmed.',
      );
    }
  }

  Future<void> clearPersonPresence() async {
    final response = await _client.delete(
      Uri.parse(
        '${_config.httpBaseUrl}/people/presence/current',
      ),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Clear person presence failed: ${response.statusCode}',
      );
    }
  }

  Future<void> deletePerson(
    String personId,
  ) async {
    final response = await _client.delete(
      Uri.parse(
        '${_config.httpBaseUrl}/people/$personId',
      ),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Delete person failed: ${response.statusCode}',
      );
    }
  }

  void dispose() {
    _client.close();
  }
}
