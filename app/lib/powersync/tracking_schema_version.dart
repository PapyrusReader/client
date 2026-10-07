/// Multiple-book scopes require tracking schema v2; ordinary tracking stays v1.
int requiredTrackingSchemaVersion(Map<String, dynamic> payload) {
  final definition = payload['definition'];
  final goal = definition is Map ? definition : payload;
  return (goal['book_ids'] as List? ?? const []).length > 1 ? 2 : 1;
}
