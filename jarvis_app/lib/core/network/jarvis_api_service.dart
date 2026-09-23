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

class JarvisMusicTrack {
  const JarvisMusicTrack({
    required this.query,
    required this.provider,
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.watchUrl,
  });

  final String query;
  final String provider;
  final String videoId;
  final String title;
  final String author;
  final String thumbnailUrl;
  final String watchUrl;
}

class JarvisPhoneReceptionistStatus {
  const JarvisPhoneReceptionistStatus({
    required this.configured,
    required this.provider,
    required this.phoneNumber,
    required this.activeCalls,
  });

  final bool configured;
  final String provider;
  final String phoneNumber;
  final int activeCalls;
}

class JarvisPhoneReceptionistMessage {
  const JarvisPhoneReceptionistMessage({
    required this.callId,
    required this.fromNumber,
    required this.toNumber,
    required this.callerName,
    required this.callbackNumber,
    required this.urgent,
    required this.summary,
    required this.transcript,
    required this.assistantTranscript,
    required this.status,
    required this.startedAt,
    required this.completedAt,
  });

  final String callId;
  final String fromNumber;
  final String toNumber;
  final String callerName;
  final String callbackNumber;
  final bool urgent;
  final String summary;
  final String transcript;
  final String assistantTranscript;
  final String status;
  final DateTime? startedAt;
  final DateTime? completedAt;

  factory JarvisPhoneReceptionistMessage.fromJson(
    Map<String, dynamic> json,
  ) {
    return JarvisPhoneReceptionistMessage(
      callId: json['call_id']?.toString() ?? '',
      fromNumber:
          json['from_number']?.toString() ?? '',
      toNumber:
          json['to_number']?.toString() ?? '',
      callerName:
          json['caller_name']?.toString() ?? '',
      callbackNumber:
          json['callback_number']?.toString() ?? '',
      urgent: json['urgent'] == true,
      summary: json['summary']?.toString() ?? '',
      transcript:
          json['transcript']?.toString() ?? '',
      assistantTranscript:
          json['assistant_transcript']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      startedAt: DateTime.tryParse(
        json['started_at']?.toString() ?? '',
      ),
      completedAt: DateTime.tryParse(
        json['completed_at']?.toString() ?? '',
      ),
    );
  }
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

  Future<JarvisPhoneReceptionistStatus>
      phoneReceptionistStatus() async {
    final response = await _client.get(
      Uri.parse(
        '${_config.httpBaseUrl}/v1/phone/status',
      ),
      headers: _headers,
    );

    final Object? decoded =
        jsonDecode(response.body);

    if (response.statusCode != 200) {
      final String detail = decoded is Map
          ? decoded['detail']?.toString() ??
              'Phone receptionist status failed.'
          : 'Phone receptionist status failed.';
      throw StateError(detail);
    }

    if (decoded is! Map) {
      throw const FormatException(
        'Invalid phone receptionist status.',
      );
    }

    final Map<String, dynamic> data =
        Map<String, dynamic>.from(decoded);

    return JarvisPhoneReceptionistStatus(
      configured: data['configured'] == true,
      provider:
          data['provider']?.toString() ?? '',
      phoneNumber:
          data['phone_number']?.toString() ?? '',
      activeCalls:
          (data['active_calls'] as num?)
                  ?.toInt() ??
              0,
    );
  }

  Future<List<JarvisPhoneReceptionistMessage>>
      phoneReceptionistMessages() async {
    final response = await _client.get(
      Uri.parse(
        '${_config.httpBaseUrl}/v1/phone/messages',
      ),
      headers: _headers,
    );

    final Object? decoded =
        jsonDecode(response.body);

    if (response.statusCode != 200) {
      final String detail = decoded is Map
          ? decoded['detail']?.toString() ??
              'Phone receptionist messages failed.'
          : 'Phone receptionist messages failed.';
      throw StateError(detail);
    }

    if (decoded is! Map) {
      throw const FormatException(
        'Invalid phone receptionist messages response.',
      );
    }

    final Object? raw = decoded['messages'];
    if (raw is! List) {
      return const <JarvisPhoneReceptionistMessage>[];
    }

    return raw
        .whereType<Map>()
        .map(
          (Map item) =>
              JarvisPhoneReceptionistMessage.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  Future<JarvisMusicTrack> searchMusic(
    String query,
  ) async {
    final String normalized = query.trim();

    if (normalized.isEmpty) {
      throw ArgumentError(
        'A song, artist, or album is required.',
      );
    }

    final response = await _client.post(
      Uri.parse(
        '${_config.httpBaseUrl}/v1/music/search',
      ),
      headers: _headers,
      body: jsonEncode(<String, dynamic>{
        'query': normalized,
      }),
    );

    final Object? decoded =
        jsonDecode(response.body);

    if (response.statusCode != 200) {
      final String detail = decoded is Map
          ? decoded['detail']?.toString() ??
              'Music search failed.'
          : 'Music search failed.';
      throw StateError(
        'Music search failed: $detail',
      );
    }

    if (decoded is! Map) {
      throw const FormatException(
        'Invalid music search response.',
      );
    }

    final Map<String, dynamic> data =
        Map<String, dynamic>.from(decoded);

    final String videoId =
        data['video_id']?.toString() ?? '';

    if (videoId.length != 11) {
      throw const FormatException(
        'Music search returned an invalid video ID.',
      );
    }

    return JarvisMusicTrack(
      query: data['query']?.toString() ?? normalized,
      provider:
          data['provider']?.toString() ?? 'youtube',
      videoId: videoId,
      title: data['title']?.toString() ?? normalized,
      author: data['author']?.toString() ?? '',
      thumbnailUrl:
          data['thumbnail_url']?.toString() ?? '',
      watchUrl:
          data['watch_url']?.toString() ?? '',
    );
  }


  Future<String> createRealtimeClientSecret({
    String voice = 'cedar',
    String mood = 'confident',
    String context = '',
  }) async {
    final response = await _client.post(
      Uri.parse(
        '${_config.httpBaseUrl}/v1/realtime/client-secret',
      ),
      headers: _headers,
      body: jsonEncode(<String, dynamic>{
        'voice': voice,
        'mood': mood,
        'context': context,
      }),
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
