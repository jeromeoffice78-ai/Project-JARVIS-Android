import 'package:flutter_test/flutter_test.dart';
import 'package:project_jarvis/features/autonomy/jarvis_autonomy_intents.dart';

void main() {
  test('Explicit text and voice commands produce bounded goal requests', () {
    expect(
      parseJarvisAutonomousGoal('Jarvis, autonomously organize my notes'),
      'organize my notes',
    );
    expect(
      parseJarvisAutonomousGoal('Hey Jarvis work autonomously on the report'),
      'the report',
    );
    expect(
      parseJarvisAutonomousGoal('Take care of my weekly planning'),
      'my weekly planning',
    );
  });

  test('Normal conversation never activates autonomous mode', () {
    expect(parseJarvisAutonomousGoal('Tell me about autonomous agents'), isNull);
    expect(parseJarvisAutonomousGoal('Hey Jarvis, what time is it?'), isNull);
    expect(parseJarvisAutonomousGoal('Jarvis, autonomously '), isNull);
  });
}
