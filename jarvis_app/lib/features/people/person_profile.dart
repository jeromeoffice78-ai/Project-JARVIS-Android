class PersonProfile {
  const PersonProfile({
    required this.personId,
    required this.displayName,
    required this.relationship,
    required this.notes,
    this.lastSeenAt,
  });

  final String personId;
  final String displayName;
  final String relationship;
  final String notes;
  final String? lastSeenAt;

  factory PersonProfile.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersonProfile(
      personId: json['person_id']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      relationship: json['relationship']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      lastSeenAt: json['last_seen_at']?.toString(),
    );
  }
}
