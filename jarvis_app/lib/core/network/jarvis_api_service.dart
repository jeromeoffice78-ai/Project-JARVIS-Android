import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/jarvis_config.dart';
import '../../features/people/person_profile.dart';

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
