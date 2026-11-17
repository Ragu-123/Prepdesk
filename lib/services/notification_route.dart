import 'dart:convert';

/// Keeps an occurrence's Android ID separate from its parent reminder ID.
class NotificationRoute {
  final int occurrenceId;
  final int groupId;
  final String title;
  const NotificationRoute(this.occurrenceId, this.groupId, this.title);

  String encode() => 'nyro:alarm:${jsonEncode({
    'id': occurrenceId, 'group': groupId, 'title': title,
  })}';

  static NotificationRoute? parse(String payload) {
    if (payload.startsWith('nyro:alarm:')) {
      try {
        final data = jsonDecode(payload.substring('nyro:alarm:'.length)) as Map<String, dynamic>;
        return NotificationRoute(data['id'] as int, data['group'] as int, data['title'] as String);
      } catch (_) { return null; }
    }
    if (payload.startsWith('route:alarm:')) {
      final parts = payload.split(':');
      final id = parts.length > 2 ? int.tryParse(parts[2]) : null;
      if (id != null) return NotificationRoute(id, id, parts.skip(3).join(':'));
    }
    return null;
  }
}
