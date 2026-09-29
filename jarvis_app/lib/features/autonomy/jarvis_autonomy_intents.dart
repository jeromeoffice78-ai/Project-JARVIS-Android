/// Converts only an explicit voice or typed directive into an autonomous
/// goal. Ordinary requests must never start an agent without intent.
String? parseJarvisAutonomousGoal(String text) {
  final String clean = text.trim();
  final RegExpMatch? match = RegExp(
    r'^(?:hey\s+)?(?:jarvis[,:]?\s*)?'
    r'(?:autonomously\s+|work autonomously on\s+|take care of\s+)'
    r'(.+)$',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(clean);
  final goal = match?.group(1)?.trim() ?? '';
  return goal.isEmpty ? null : goal;
}
