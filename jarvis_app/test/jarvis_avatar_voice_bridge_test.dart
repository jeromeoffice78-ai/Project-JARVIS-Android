import 'package:flutter_test/flutter_test.dart';
import 'package:project_jarvis/features/chat/jarvis_chat_controller.dart';
import 'package:project_jarvis/features/presence/jarvis_avatar_voice_bridge.dart';
import 'package:project_jarvis/features/realtime/jarvis_realtime_voice_service.dart';
import 'package:project_jarvis/features/voice/jarvis_voice_service.dart';

void main() {
  const JarvisRealtimeVoiceState idle = JarvisRealtimeVoiceState.initial();
  const JarvisChatState chatIdle = JarvisChatState.initial();

  test('Avatar speaks when normal Android text-to-speech is speaking', () {
    final result = avatarStateForConversation(
      realtime: idle,
      localVoice: JarvisVoiceState.speaking,
      chat: chatIdle,
    );
    expect(result.activity, JarvisConversationActivity.speaking);
  });

  test('Avatar listens to standard Android speech recognition', () {
    final result = avatarStateForConversation(
      realtime: idle,
      localVoice: JarvisVoiceState.listening,
      chat: chatIdle,
    );
    expect(result.activity, JarvisConversationActivity.listening);
  });

  test('Avatar visibly thinks while ordinary text chat is waiting', () {
    final result = avatarStateForConversation(
      realtime: idle,
      localVoice: JarvisVoiceState.idle,
      chat: const JarvisChatState(
        status: JarvisChatStatus.thinking,
        responseText: '',
      ),
    );
    expect(result.activity, JarvisConversationActivity.thinking);
  });

  test('Connected realtime conversation owns avatar state over local TTS', () {
    final live = idle.copyWith(
      status: JarvisRealtimeVoiceStatus.connected,
      activity: JarvisConversationActivity.listening,
    );
    final result = avatarStateForConversation(
      realtime: live,
      localVoice: JarvisVoiceState.speaking,
      chat: chatIdle,
    );
    expect(result.activity, JarvisConversationActivity.listening);
  });
}
