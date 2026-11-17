import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/services/notification_route.dart';

void main() {
  test('Alarm titles retain punctuation and their parent reminder after snooze', () {
    const title = 'Review: arrays / strings: chapter 2';
    final route = NotificationRoute.parse(const NotificationRoute(450008, 45, title).encode())!;
    expect(route.title, title);
    expect(route.groupId, 45);
    expect(route.occurrenceId, 450008);
    final snoozed = NotificationRoute.parse(NotificationRoute(900000, route.groupId, route.title).encode())!;
    expect(snoozed.groupId, 45);
    expect(snoozed.occurrenceId, 900000);
  });
  test('Older installed notifications remain readable', () {
    final route = NotificationRoute.parse('route:alarm:42:Study: chapter 3')!;
    expect(route.title, 'Study: chapter 3');
    expect(route.groupId, 42);
    expect(NotificationRoute.parse('nyro:alarm:invalid'), isNull);
    expect(NotificationRoute.parse('route:keep_note:private'), isNull);
  });
}
