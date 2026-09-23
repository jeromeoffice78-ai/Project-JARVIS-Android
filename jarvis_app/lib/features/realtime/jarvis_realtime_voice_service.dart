import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import '../../core/network/jarvis_api_service.dart';
import '../people/jarvis_voice_identity_service.dart';
import '../people/person_profile.dart';

enum JarvisRealtimeVoiceStatus {
  idle,
  connecting,
  connected,
  stopping,
  error,
}

enum JarvisConversationActivity {
  idle,
  listening,
  thinking,
  speaking,
}

final class JarvisRealtimeVoiceState {
  const JarvisRealtimeVoiceState({
    required this.status,
    required this.activity,
    required this.transcript,
    required this.userTranscript,
    required this.currentVoice,
    required this.mood,
    required this.autoDirector,
    required this.companionMode,
    required this.speakerName,
    this.errorMessage,
  });

  const JarvisRealtimeVoiceState.initial()
      : status = JarvisRealtimeVoiceStatus.idle,
        activity = JarvisConversationActivity.idle,
        transcript = '',
        userTranscript = '',
        currentVoice = 'cedar',
        mood = 'confident',
        autoDirector = true,
        companionMode = false,
        speakerName = '',
        errorMessage = null;

  final JarvisRealtimeVoiceStatus status;
  final JarvisConversationActivity activity;
  final String transcript;
  final String userTranscript;
  final String currentVoice;
  final String mood;
  final bool autoDirector;
  final bool companionMode;
  final String speakerName;
  final String? errorMessage;

  bool get isConnected =>
      status == JarvisRealtimeVoiceStatus.connected;

  JarvisRealtimeVoiceState copyWith({
    JarvisRealtimeVoiceStatus? status,
    JarvisConversationActivity? activity,
    String? transcript,
    String? userTranscript,
    String? currentVoice,
    String? mood,
    bool? autoDirector,
    bool? companionMode,
    String? speakerName,
    String? errorMessage,
    bool clearError = false,
  }) {
    return JarvisRealtimeVoiceState(
      status: status ?? this.status,
      activity: activity ?? this.activity,
      transcript: transcript ?? this.transcript,
      userTranscript:
          userTranscript ?? this.userTranscript,
      currentVoice:
          currentVoice ?? this.currentVoice,
      mood: mood ?? this.mood,
      autoDirector:
          autoDirector ?? this.autoDirector,
      companionMode:
          companionMode ?? this.companionMode,
      speakerName:
          speakerName ?? this.speakerName,
      errorMessage: clearError
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

final class _VoiceDirection {
  const _VoiceDirection({
    required this.voice,
    required this.mood,
    required this.companionMode,
  });

  final String voice;
  final String mood;
  final bool companionMode;
}

class JarvisRealtimeVoiceService {
  JarvisRealtimeVoiceService({
    required JarvisApiService apiService,
    required JarvisVoiceIdentityService voiceIdentityService,
    http.Client? httpClient,
  })  : _apiService = apiService,
        _voiceIdentityService = voiceIdentityService,
        _httpClient = httpClient ?? http.Client();

  static const Set<String> supportedVoices =
      <String>{
    'cedar',
    'ash',
    'echo',
    'verse',
    'marin',
    'alloy',
    'ballad',
    'coral',
    'sage',
    'shimmer',
  };

  static const Set<String> supportedMoods =
      <String>{
    'confident',
    'calm',
    'serious',
    'focused',
    'energetic',
    'warm',
    'intense',
    'companion',
  };

  final JarvisApiService _apiService;
  final JarvisVoiceIdentityService _voiceIdentityService;
  final http.Client _httpClient;

  final StreamController<JarvisRealtimeVoiceState>
      _stateController =
      StreamController<JarvisRealtimeVoiceState>
          .broadcast();

  JarvisRealtimeVoiceState _state =
      const JarvisRealtimeVoiceState.initial();

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  MediaStream? _localStream;

  final List<String> _conversationTurns =
      <String>[];
  List<PersonProfile> _knownPeople =
      const <PersonProfile>[];
  PersonProfile? _activePerson;
  String _currentAssistantTurn = '';
  bool _responseInProgress = false;
  String? _pendingVoice;
  DateTime _lastVoiceSwitchAt =
      DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;
  bool _reconnecting = false;

  Stream<JarvisRealtimeVoiceState>
      get stateStream => _stateController.stream;

  JarvisRealtimeVoiceState get state => _state;

  Future<void> start() async {
    if (_disposed ||
        _state.status ==
            JarvisRealtimeVoiceStatus.connecting ||
        _state.isConnected) {
      return;
    }

    await _refreshKnownPeople();
    await _identifySpeakerBeforeConversation();

    await _connect(
      preserveConversation: true,
    );
  }

  Future<void> setAutoDirector(
    bool enabled,
  ) async {
    _emit(
      _state.copyWith(
        autoDirector: enabled,
        clearError: true,
      ),
    );
  }

  Future<void> setVoice(
    String voice,
  ) async {
    final String normalized =
        voice.trim().toLowerCase();

    if (!supportedVoices.contains(normalized) ||
        normalized == _state.currentVoice) {
      return;
    }

    await _switchVoice(
      normalized,
      automatic: false,
    );
  }

  Future<void> setMood(
    String mood, {
    bool companionMode = false,
  }) async {
    final String normalized =
        mood.trim().toLowerCase();

    if (!supportedMoods.contains(normalized)) {
      return;
    }

    _emit(
      _state.copyWith(
        mood: normalized,
        companionMode: companionMode ||
            normalized == 'companion',
        clearError: true,
      ),
    );

    _sendMoodUpdate();
  }

  Future<void> setActiveSpeaker(
    PersonProfile? person,
  ) async {
    _activePerson = person;

    _emit(
      _state.copyWith(
        speakerName:
            person?.displayName ?? '',
        clearError: true,
      ),
    );

    if (person != null) {
      try {
        await _apiService.confirmPersonPresent(
          person.personId,
        );
      } on Object {
        // Conversation identity still works locally
        // even if the presence endpoint is unavailable.
      }

      await _apiService.saveMemory(
        text:
            'Current conversation participant: ${person.displayName}. Relationship/context: ${person.relationship}. Notes: ${person.notes}.',
        kind: 'person_identity',
        importance: 0.9,
      );

      _sendMoodUpdate();
    }
  }

  Future<void> _refreshKnownPeople() async {
    try {
      _knownPeople =
          await _apiService.listPeople();
    } on Object {
      _knownPeople =
          const <PersonProfile>[];
    }
  }

  Future<void>
      _identifySpeakerBeforeConversation() async {
    if (_knownPeople.isEmpty) {
      return;
    }

    try {
      final Set<String> enrolledIds =
          await _voiceIdentityService
              .listVoiceProfileIds();

      if (enrolledIds.isEmpty) {
        return;
      }

      final JarvisVoiceIdentityMatch match =
          await _voiceIdentityService
              .identifySpeaker();

      if (!match.matched ||
          match.personId.isEmpty) {
        return;
      }

      PersonProfile? person;
      for (final PersonProfile candidate
          in _knownPeople) {
        if (candidate.personId ==
            match.personId) {
          person = candidate;
          break;
        }
      }

      if (person == null) {
        return;
      }

      await setActiveSpeaker(person);

      _recordTurn(
        'System',
        'Voice profile matched ${person.displayName} '
            'with similarity '
            '${match.similarity.toStringAsFixed(3)}.',
      );
    } on Object {
      // Voice matching is best-effort. Failure must not
      // prevent the live conversation from starting.
    }
  }

  Future<void> _connect({
    required bool preserveConversation,
  }) async {
    _emit(
      _state.copyWith(
        status:
            JarvisRealtimeVoiceStatus.connecting,
        activity:
            JarvisConversationActivity.idle,
        transcript:
            preserveConversation
                ? _state.transcript
                : '',
        userTranscript:
            preserveConversation
                ? _state.userTranscript
                : '',
        clearError: true,
      ),
    );

    try {
      final String ephemeralSecret =
          await _apiService
              .createRealtimeClientSecret(
        voice: _state.currentVoice,
        mood: _state.mood,
        context: _continuityContext(),
      );

      await Helper
          .setSpeakerphoneOnButPreferBluetooth();

      final RTCPeerConnection pc =
          await createPeerConnection(
        <String, dynamic>{},
      );
      _peerConnection = pc;

      pc.onConnectionState =
          (RTCPeerConnectionState connectionState) {
        if (_disposed) {
          return;
        }

        if (connectionState ==
            RTCPeerConnectionState
                .RTCPeerConnectionStateConnected) {
          _emit(
            _state.copyWith(
              status:
                  JarvisRealtimeVoiceStatus
                      .connected,
              activity:
                  JarvisConversationActivity
                      .listening,
              clearError: true,
            ),
          );
        } else if (!_reconnecting &&
            (connectionState ==
                    RTCPeerConnectionState
                        .RTCPeerConnectionStateFailed ||
                connectionState ==
                    RTCPeerConnectionState
                        .RTCPeerConnectionStateDisconnected)) {
          _emit(
            _state.copyWith(
              status:
                  JarvisRealtimeVoiceStatus.error,
              activity:
                  JarvisConversationActivity.idle,
              errorMessage:
                  'Realtime voice connection was lost.',
            ),
          );
        }
      };

      final MediaStream stream =
          await navigator.mediaDevices
              .getUserMedia(
        <String, dynamic>{
          'audio': true,
          'video': false,
        },
      );
      _localStream = stream;

      for (final MediaStreamTrack track
          in stream.getAudioTracks()) {
        await pc.addTrack(track, stream);
      }

      final RTCDataChannelInit init =
          RTCDataChannelInit()
            ..ordered = true;

      final RTCDataChannel dataChannel =
          await pc.createDataChannel(
        'oai-events',
        init,
      );
      _dataChannel = dataChannel;
      dataChannel.onMessage =
          _handleDataChannelMessage;

      final RTCSessionDescription offer =
          await pc.createOffer(
        <String, dynamic>{
          'offerToReceiveAudio': true,
        },
      );

      await pc.setLocalDescription(offer);

      final String sdp = offer.sdp ?? '';
      if (sdp.isEmpty) {
        throw StateError(
          'WebRTC created no SDP offer.',
        );
      }

      final http.Response response =
          await _httpClient
              .post(
                Uri.parse(
                  'https://api.openai.com/v1/realtime/calls',
                ),
                headers: <String, String>{
                  'Authorization':
                      'Bearer $ephemeralSecret',
                  'Content-Type':
                      'application/sdp',
                },
                body: sdp,
              )
              .timeout(
                const Duration(seconds: 25),
              );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw StateError(
          'Realtime WebRTC setup failed with HTTP ${response.statusCode}.',
        );
      }

      await pc.setRemoteDescription(
        RTCSessionDescription(
          response.body,
          'answer',
        ),
      );

      _emit(
        _state.copyWith(
          status:
              JarvisRealtimeVoiceStatus.connected,
          activity:
              JarvisConversationActivity.listening,
          clearError: true,
        ),
      );

      _sendMoodUpdate();
    } on Object catch (error) {
      await _closeTransport();

      _emit(
        _state.copyWith(
          status: JarvisRealtimeVoiceStatus.error,
          activity:
              JarvisConversationActivity.idle,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  void _handleDataChannelMessage(
    RTCDataChannelMessage message,
  ) {
    if (_disposed || message.isBinary) {
      return;
    }

    try {
      final Object? decoded =
          jsonDecode(message.text);
      if (decoded is! Map) {
        return;
      }

      final Map<String, dynamic> event =
          Map<String, dynamic>.from(decoded);
      final String type =
          event['type']?.toString() ?? '';

      if (type ==
          'input_audio_buffer.speech_started') {
        _emit(
          _state.copyWith(
            activity:
                JarvisConversationActivity
                    .listening,
            clearError: true,
          ),
        );
        return;
      }

      if (type ==
          'input_audio_buffer.speech_stopped') {
        _emit(
          _state.copyWith(
            activity:
                JarvisConversationActivity
                    .thinking,
            clearError: true,
          ),
        );
        return;
      }

      if (type == 'response.created') {
        _responseInProgress = true;
        _currentAssistantTurn = '';

        _emit(
          _state.copyWith(
            activity:
                JarvisConversationActivity
                    .thinking,
            clearError: true,
          ),
        );
        return;
      }

      if (type ==
          'conversation.item.input_audio_transcription.completed') {
        final String userText =
            event['transcript']
                    ?.toString()
                    .trim() ??
                '';

        if (userText.isNotEmpty) {
          _recordTurn(
            _activePerson?.displayName ??
                'You',
            userText,
          );

          _emit(
            _state.copyWith(
              userTranscript: userText,
              clearError: true,
            ),
          );

          unawaited(
            _learnSpeakerFromIntroduction(
              userText,
            ),
          );

          if (_state.autoDirector) {
            _autonomouslyDirectVoice(
              userText,
            );
          }
        }
        return;
      }

      if (type ==
              'response.output_audio_transcript.delta' ||
          type ==
              'response.output_text.delta') {
        final String delta =
            event['delta']?.toString() ?? '';

        if (delta.isNotEmpty) {
          _currentAssistantTurn += delta;

          _emit(
            _state.copyWith(
              activity:
                  JarvisConversationActivity
                      .speaking,
              transcript:
                  _state.transcript + delta,
              clearError: true,
            ),
          );
        }
        return;
      }

      if (type ==
          'response.output_audio_transcript.done') {
        final String finalText =
            event['transcript']
                    ?.toString()
                    .trim() ??
                _currentAssistantTurn.trim();

        if (finalText.isNotEmpty) {
          _currentAssistantTurn =
              finalText;
        }
        return;
      }

      if (type == 'response.done') {
        _responseInProgress = false;

        final String assistantText =
            _currentAssistantTurn.trim();

        if (assistantText.isNotEmpty) {
          _recordTurn(
            'Jarvis',
            assistantText,
          );
        }

        _currentAssistantTurn = '';

        _emit(
          _state.copyWith(
            activity:
                JarvisConversationActivity
                    .listening,
            clearError: true,
          ),
        );

        final String? pending =
            _pendingVoice;
        _pendingVoice = null;

        if (pending != null &&
            pending != _state.currentVoice) {
          unawaited(
            _switchVoice(
              pending,
              automatic: true,
            ),
          );
        }
        return;
      }

      if (type == 'error') {
        final Object? rawError =
            event['error'];

        final String errorText =
            rawError is Map
                ? rawError['message']
                        ?.toString() ??
                    'Realtime voice error.'
                : 'Realtime voice error.';

        _emit(
          _state.copyWith(
            status:
                JarvisRealtimeVoiceStatus
                    .error,
            activity:
                JarvisConversationActivity
                    .idle,
            errorMessage: errorText,
          ),
        );
      }
    } on FormatException {
      // Ignore malformed/non-JSON data-channel events.
    }
  }

  Future<void> _learnSpeakerFromIntroduction(
    String userText,
  ) async {
    final RegExp introduction = RegExp(
      r"\b(?:my name is|i am|i'm|this is)\s+([a-z][a-z' -]{1,40})",
      caseSensitive: false,
    );

    final RegExpMatch? match =
        introduction.firstMatch(userText);

    if (match == null) {
      return;
    }

    String candidate =
        match.group(1)?.trim() ?? '';

    candidate = candidate
        .split(
          RegExp(
            r'[,.;!?]|\b(?:and|but|because|so)\b',
            caseSensitive: false,
          ),
        )
        .first
        .trim();

    final List<String> parts = candidate
        .split(RegExp(r'\s+'))
        .where(
          (String part) =>
              part.trim().isNotEmpty,
        )
        .take(3)
        .toList();

    if (parts.isEmpty) {
      return;
    }

    final String displayName = parts
        .map(
          (String part) =>
              part[0].toUpperCase() +
              part.substring(1),
        )
        .join(' ');

    PersonProfile? known;
    for (final PersonProfile person
        in _knownPeople) {
      if (person.displayName
              .trim()
              .toLowerCase() ==
          displayName.toLowerCase()) {
        known = person;
        break;
      }
    }

    if (known == null) {
      try {
        known = await _apiService.createPerson(
          displayName: displayName,
          relationship: 'Conversation contact',
          notes:
              'Name learned when this person introduced themselves to Jarvis.',
        );

        _knownPeople = <PersonProfile>[
          ..._knownPeople,
          known,
        ];
      } on Object {
        return;
      }
    }

    await setActiveSpeaker(known);

    _recordTurn(
      'System',
      'Current speaker identified by introduction as ${known.displayName}.',
    );
  }

  void _autonomouslyDirectVoice(
    String userText,
  ) {
    final _VoiceDirection direction =
        _directionFor(userText);

    final bool wasCompanion =
        _state.companionMode;

    final bool moodChanged =
        direction.mood != _state.mood ||
        direction.companionMode !=
            _state.companionMode;

    if (moodChanged) {
      _emit(
        _state.copyWith(
          mood: direction.mood,
          companionMode:
              direction.companionMode,
          clearError: true,
        ),
      );

      _sendMoodUpdate();
    }

    if (direction.voice ==
        _state.currentVoice) {
      return;
    }

    final Duration sinceLast =
        DateTime.now().difference(
      _lastVoiceSwitchAt,
    );

    final bool companionPriority =
        direction.companionMode &&
        !wasCompanion;

    if (sinceLast <
            const Duration(minutes: 2) &&
        !companionPriority) {
      return;
    }

    if (_responseInProgress) {
      _pendingVoice =
          direction.voice;
      return;
    }

    unawaited(
      _switchVoice(
        direction.voice,
        automatic: true,
      ),
    );
  }

  _VoiceDirection _directionFor(
    String userText,
  ) {
    final String text =
        userText.toLowerCase();

    final bool companion = RegExp(
      r"\b(i need someone to talk to|talk to me|just talk|listen to me|i feel alone|feeling alone|lonely|rough day|bad day|i am sad|i'm sad|upset|heartbroken|stressed out|need to vent|can i vent|stay with me)\b",
    ).hasMatch(text);

    if (companion) {
      return const _VoiceDirection(
        voice: 'cedar',
        mood: 'companion',
        companionMode: true,
      );
    }

    final bool serious = RegExp(
      r'\b(serious|court|lawyer|legal|police|debt|deadline|danger|important|bad news|emergency)\b',
    ).hasMatch(text);

    if (serious) {
      return const _VoiceDirection(
        voice: 'echo',
        mood: 'serious',
        companionMode: false,
      );
    }

    final bool focused = RegExp(
      r'\b(analyze|research|calculate|debug|code|fix|diagnose|compare|plan|build|technical|step by step)\b',
    ).hasMatch(text);

    if (focused) {
      return const _VoiceDirection(
        voice: 'ash',
        mood: 'focused',
        companionMode: false,
      );
    }

    final bool intense = RegExp(
      r'\b(now|immediately|urgent|hurry|right away|critical|warning)\b',
    ).hasMatch(text);

    if (intense) {
      return const _VoiceDirection(
        voice: 'ash',
        mood: 'intense',
        companionMode: false,
      );
    }

    final bool energetic = RegExp(
      r'\b(great|awesome|excellent|we did it|let.s go|good news|excited)\b',
    ).hasMatch(text);

    if (energetic) {
      return const _VoiceDirection(
        voice: 'verse',
        mood: 'energetic',
        companionMode: false,
      );
    }

    return const _VoiceDirection(
      voice: 'cedar',
      mood: 'confident',
      companionMode: false,
    );
  }

  Future<void> _switchVoice(
    String voice, {
    required bool automatic,
  }) async {
    if (_disposed ||
        !supportedVoices.contains(voice) ||
        voice == _state.currentVoice) {
      return;
    }

    _reconnecting = true;

    try {
      await _closeTransport();

      _lastVoiceSwitchAt =
          DateTime.now();

      _emit(
        _state.copyWith(
          currentVoice: voice,
          status:
              JarvisRealtimeVoiceStatus
                  .connecting,
          activity:
              JarvisConversationActivity.idle,
          clearError: true,
        ),
      );

      await _connect(
        preserveConversation: true,
      );
    } finally {
      _reconnecting = false;
    }
  }

  void _sendMoodUpdate() {
    final RTCDataChannel? channel =
        _dataChannel;

    if (channel == null ||
        channel.state !=
            RTCDataChannelState
                .RTCDataChannelOpen) {
      return;
    }

    final String speaker =
        _activePerson?.displayName ?? '';

    final String relationship =
        _activePerson?.relationship ?? '';

    final String companionInstruction =
        _state.companionMode
            ? 'Companion mode is active. Listen first. Let the person finish. Ask natural follow-up questions. Do not turn every feeling into a checklist or a solution. Offer advice only when it fits or is requested. Stay warm, grounded, and conversational.'
            : 'Use a capable assistant style, but remain conversational and natural.';

    final String personInstruction =
        speaker.isEmpty
            ? 'The primary user is speaking unless another person clearly introduces themselves or a saved profile is explicitly selected.'
            : 'You are currently talking with ${speaker}. Relationship/context: ${relationship}. Use their name naturally when appropriate and keep their conversation context distinct from other people.';

    final String moodInstruction =
        _moodInstruction(_state.mood);

    final Map<String, dynamic> update =
        <String, dynamic>{
      'type': 'session.update',
      'session': <String, dynamic>{
        'type': 'realtime',
        'instructions':
            'You are JARVIS, a male personal AI assistant with a cool, grounded presence. ${moodInstruction} ${companionInstruction} ${personInstruction} Remember recent conversation context and follow-ups. Be honest that you are Jarvis, an AI assistant; do not pretend to be a human. Device/tool actions must be verified before claiming success.',
      },
    };

    channel.send(
      RTCDataChannelMessage(
        jsonEncode(update),
      ),
    );
  }

  String _moodInstruction(
    String mood,
  ) {
    switch (mood) {
      case 'calm':
        return 'Sound calm, grounded, patient, and reassuring.';
      case 'serious':
        return 'Sound serious, composed, firm, and measured.';
      case 'focused':
        return 'Sound analytical, alert, efficient, and precise.';
      case 'energetic':
        return 'Sound energized, upbeat, decisive, and action-oriented.';
      case 'warm':
        return 'Sound warm, friendly, and conversational.';
      case 'intense':
        return 'Sound urgent and forceful but controlled; never shout.';
      case 'companion':
        return 'Sound warm, steady, masculine, present, and easy to talk to.';
      case 'confident':
      default:
        return 'Sound masculine, cool, self-assured, concise, and capable.';
    }
  }

  void _recordTurn(
    String speaker,
    String text,
  ) {
    final String normalized =
        text.trim();

    if (normalized.isEmpty) {
      return;
    }

    _conversationTurns.add(
      '${speaker}: ${normalized}',
    );

    if (_conversationTurns.length > 24) {
      _conversationTurns.removeRange(
        0,
        _conversationTurns.length - 24,
      );
    }
  }

  String _continuityContext() {
    final List<String> context =
        <String>[];

    if (_activePerson != null) {
      context.add(
        'Current person: ${_activePerson!.displayName}. Relationship/context: ${_activePerson!.relationship}. Notes: ${_activePerson!.notes}.',
      );
    }

    if (_conversationTurns.isNotEmpty) {
      context.add(
        'Recent conversation:\n${_conversationTurns.takeLast(12).join('\n')}',
      );
    }

    return context.join('\n\n');
  }

  Future<void> mute(
    bool muted,
  ) async {
    final MediaStream? stream =
        _localStream;

    if (stream == null) {
      return;
    }

    for (final MediaStreamTrack track
        in stream.getAudioTracks()) {
      track.enabled = !muted;
    }
  }

  Future<void> stop() async {
    if (_disposed) {
      return;
    }

    _emit(
      _state.copyWith(
        status:
            JarvisRealtimeVoiceStatus.stopping,
        activity:
            JarvisConversationActivity.idle,
      ),
    );

    final String continuity =
        _continuityContext();

    await _closeTransport();

    if (continuity.trim().isNotEmpty) {
      try {
        await _apiService.saveMemory(
          text:
              'Recent Jarvis voice conversation context:\n${continuity}',
          kind: _activePerson == null
              ? 'conversation'
              : 'person_conversation',
          importance:
              _activePerson == null ? 0.6 : 0.75,
        );
      } on Object {
        // Ending a voice session must not fail because
        // memory persistence is unavailable.
      }
    }

    _emit(
      const JarvisRealtimeVoiceState.initial(),
    );
  }

  Future<void> _closeTransport() async {
    final RTCDataChannel? channel =
        _dataChannel;
    _dataChannel = null;

    if (channel != null) {
      try {
        await channel.close();
      } on Object {
        // Continue shutdown.
      }
    }

    final MediaStream? stream =
        _localStream;
    _localStream = null;

    if (stream != null) {
      for (final MediaStreamTrack track
          in stream.getTracks()) {
        try {
          await track.stop();
        } on Object {
          // Continue shutdown.
        }
      }

      try {
        await stream.dispose();
      } on Object {
        // Continue shutdown.
      }
    }

    final RTCPeerConnection? pc =
        _peerConnection;
    _peerConnection = null;

    if (pc != null) {
      try {
        await pc.close();
      } on Object {
        // Continue shutdown.
      }

      try {
        await pc.dispose();
      } on Object {
        // Continue shutdown.
      }
    }

    try {
      await Helper
          .clearAndroidCommunicationDevice();
    } on Object {
      // Android-only cleanup is best effort.
    }
  }

  void _emit(
    JarvisRealtimeVoiceState next,
  ) {
    if (_disposed) {
      return;
    }

    _state = next;

    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    await _closeTransport();
    _disposed = true;
    _httpClient.close();
    await _stateController.close();
  }
}

extension _IterableTakeLast<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final List<T> values = toList();

    if (values.length <= count) {
      return values;
    }

    return values.sublist(
      values.length - count,
    );
  }
}
