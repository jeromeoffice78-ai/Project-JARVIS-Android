import '../realtime/jarvis_realtime_voice_service.dart';

enum JarvisAvatarExpression {
  neutral,
  attentive,
  thinking,
  speaking,
  warm,
  confident,
  serious,
  energetic,
  intense,
}

enum JarvisAvatarMotion {
  still,
  breathe,
  pace,
  approach,
}

final class JarvisAvatarBehavior {
  const JarvisAvatarBehavior({
    required this.expression,
    required this.motion,
    required this.label,
    required this.energy,
  });

  final JarvisAvatarExpression expression;
  final JarvisAvatarMotion motion;
  final String label;
  final double energy;

  factory JarvisAvatarBehavior.fromVoice(
    JarvisRealtimeVoiceState voice,
  ) {
    if (voice.companionMode) {
      return JarvisAvatarBehavior(
        expression: voice.activity ==
                JarvisConversationActivity.listening
            ? JarvisAvatarExpression.attentive
            : JarvisAvatarExpression.warm,
        motion: JarvisAvatarMotion.breathe,
        label: voice.activity ==
                JarvisConversationActivity.listening
            ? 'Listening closely'
            : 'Warm companion',
        energy: 0.35,
      );
    }

    switch (voice.activity) {
      case JarvisConversationActivity.listening:
        return const JarvisAvatarBehavior(
          expression: JarvisAvatarExpression.attentive,
          motion: JarvisAvatarMotion.breathe,
          label: 'Listening',
          energy: 0.35,
        );
      case JarvisConversationActivity.thinking:
        return const JarvisAvatarBehavior(
          expression: JarvisAvatarExpression.thinking,
          motion: JarvisAvatarMotion.pace,
          label: 'Thinking',
          energy: 0.5,
        );
      case JarvisConversationActivity.speaking:
        return JarvisAvatarBehavior(
          expression: _expressionForMood(voice.mood),
          motion: voice.mood == 'energetic' ||
                  voice.mood == 'intense'
              ? JarvisAvatarMotion.approach
              : JarvisAvatarMotion.breathe,
          label: _labelForMood(voice.mood),
          energy: _energyForMood(voice.mood),
        );
      case JarvisConversationActivity.idle:
        return JarvisAvatarBehavior(
          expression: _expressionForMood(voice.mood),
          motion: JarvisAvatarMotion.still,
          label: 'Standing by',
          energy: 0.2,
        );
    }
  }

  static JarvisAvatarExpression _expressionForMood(
    String mood,
  ) {
    switch (mood) {
      case 'warm':
      case 'companion':
        return JarvisAvatarExpression.warm;
      case 'serious':
        return JarvisAvatarExpression.serious;
      case 'focused':
        return JarvisAvatarExpression.thinking;
      case 'energetic':
        return JarvisAvatarExpression.energetic;
      case 'intense':
        return JarvisAvatarExpression.intense;
      case 'confident':
      case 'calm':
      default:
        return JarvisAvatarExpression.confident;
    }
  }

  static String _labelForMood(String mood) {
    switch (mood) {
      case 'warm':
      case 'companion':
        return 'Warm';
      case 'serious':
        return 'Serious';
      case 'focused':
        return 'Focused';
      case 'energetic':
        return 'Energized';
      case 'intense':
        return 'Urgent';
      case 'calm':
        return 'Calm';
      case 'confident':
      default:
        return 'Confident';
    }
  }

  static double _energyForMood(String mood) {
    switch (mood) {
      case 'energetic':
        return 0.95;
      case 'intense':
        return 0.9;
      case 'focused':
      case 'serious':
        return 0.65;
      case 'warm':
      case 'companion':
        return 0.4;
      case 'calm':
        return 0.25;
      case 'confident':
      default:
        return 0.5;
    }
  }
}
