import '../chat/jarvis_chat_controller.dart';
import '../autonomy/jarvis_autonomy_controller.dart';
import '../realtime/jarvis_realtime_voice_service.dart';
import '../voice/jarvis_voice_service.dart';

/// Use the same physical playback state that drives Android TTS.
/// In earlier builds, the avatar only watched Realtime WebRTC activity,
/// so typed answers spoken by Flutter TTS left the character motionless.
JarvisRealtimeVoiceState avatarStateForConversation({
  required JarvisRealtimeVoiceState realtime,
  required JarvisVoiceState localVoice,
  required JarvisChatState chat,
  JarvisAutonomyState autonomy = const JarvisAutonomyState.initial(),
}) {
  if (realtime.isConnected) return realtime;
  final JarvisConversationActivity activity = switch (localVoice) {
    JarvisVoiceState.speaking => JarvisConversationActivity.speaking,
    JarvisVoiceState.listening => JarvisConversationActivity.listening,
    _ => (chat.isGenerating || autonomy.isActive)
        ? JarvisConversationActivity.thinking
        : JarvisConversationActivity.idle,
  };
  return realtime.copyWith(
    activity: activity,
    mood: autonomy.isActive && activity == JarvisConversationActivity.thinking
        ? 'focused'
        : realtime.mood,
    remoteAudioLevelAvailable: false,
    remoteAudioLevel: 0,
    transcript: chat.responseText,
  );
}
