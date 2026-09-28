import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_jarvis/features/chat/jarvis_chat_controller.dart';
import 'package:project_jarvis/features/voice/jarvis_voice_controller.dart';
import 'package:project_jarvis/features/voice/jarvis_voice_service.dart';

class FakeChatController implements JarvisChatController {
  final StreamController<JarvisChatState> _events =
      StreamController<JarvisChatState>.broadcast();
  int _counter = 0;

  @override
  Stream<JarvisChatState> get stateStream => _events.stream;

  @override
  String? askJarvis(String query) => 'test-request-${++_counter}';

  void sendCompleted(String requestId, String reply) {
    _events.add(JarvisChatState(
      status: JarvisChatStatus.completed,
      responseText: reply,
      requestId: requestId,
    ));
  }

  Future<void> close() => _events.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeVoiceService extends JarvisVoiceService {
  final StreamController<String> _transcripts =
      StreamController<String>.broadcast();
  final StreamController<JarvisVoiceState> _states =
      StreamController<JarvisVoiceState>.broadcast();
  final List<String> spoken = <String>[];

  @override
  Stream<String> get finalTranscriptStream => _transcripts.stream;

  @override
  Stream<JarvisVoiceState> get stateStream => _states.stream;

  @override
  JarvisVoiceState get state => JarvisVoiceState.idle;

  @override
  bool get isListening => false;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> cancelListening() async {}

  @override
  Future<void> startListening({String? localeId}) async {}

  Future<void> close() async {
    await _transcripts.close();
    await _states.close();
  }
}

Future<void> flushBroadcasts() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Chat replies are spoken when Spoken Replies is on', () async {
    final FakeChatController chat = FakeChatController();
    final FakeVoiceService voice = FakeVoiceService();
    final JarvisVoiceController controller = JarvisVoiceController(
      voiceService: voice,
      chatController: chat,
    );
    try {
      // The typed Chat request did not originate from voice.
      chat.sendCompleted('typed-1', 'Hello Jerome. I can hear you.');
      await flushBroadcasts();
      expect(voice.spoken, <String>['Hello Jerome. I can hear you.']);

      // A repeated completion for the same request must not speak twice.
      chat.sendCompleted('typed-1', 'Hello Jerome. I can hear you.');
      await flushBroadcasts();
      expect(voice.spoken.length, 1);
    } finally {
      await controller.dispose();
      await chat.close();
      await voice.close();
    }
  });

  test('Spoken Replies toggle silences typed Chat answers', () async {
    final FakeChatController chat = FakeChatController();
    final FakeVoiceService voice = FakeVoiceService();
    final JarvisVoiceController controller = JarvisVoiceController(
      voiceService: voice,
      chatController: chat,
    );
    try {
      controller.setSpokenReplies(false);
      chat.sendCompleted('typed-2', 'This answer is visual only.');
      await flushBroadcasts();
      expect(voice.spoken, isEmpty);
    } finally {
      await controller.dispose();
      await chat.close();
      await voice.close();
    }
  });

  test('Voice-initiated answer is still spoken once', () async {
    final FakeChatController chat = FakeChatController();
    final FakeVoiceService voice = FakeVoiceService();
    final JarvisVoiceController controller = JarvisVoiceController(
      voiceService: voice,
      chatController: chat,
    );
    try {
      final String? id = controller.submitVoiceCommand('Hey Jarvis');
      expect(id, isNotNull);
      chat.sendCompleted(id!, 'Yes, Sir?');
      await flushBroadcasts();
      expect(voice.spoken, <String>['Yes, Sir?']);
    } finally {
      await controller.dispose();
      await chat.close();
      await voice.close();
    }
  });

  test('A cancelled request never reads an error aloud', () async {
    final FakeChatController chat = FakeChatController();
    final FakeVoiceService voice = FakeVoiceService();
    final JarvisVoiceController controller = JarvisVoiceController(
      voiceService: voice,
      chatController: chat,
    );
    try {
      chat._events.add(const JarvisChatState(
        status: JarvisChatStatus.error,
        responseText: 'Provider failed',
        requestId: 'typed-error',
      ));
      await flushBroadcasts();
      expect(voice.spoken, isEmpty);
    } finally {
      await controller.dispose();
      await chat.close();
      await voice.close();
    }
  });
}
