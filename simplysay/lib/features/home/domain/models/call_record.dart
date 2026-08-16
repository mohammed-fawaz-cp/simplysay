enum CallType { missed, incoming, outgoing, message }

class CallRecord {
  final String id;
  final String name;
  final String? avatarUrl;
  final String initials;
  final CallType type;
  final String subtitle;
  final String timestamp;

  const CallRecord({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.initials,
    required this.type,
    required this.subtitle,
    required this.timestamp,
  });
}
