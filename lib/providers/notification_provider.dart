import 'package:flutter/foundation.dart';

enum NotificationSeverity { info, warning, critical }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.severity,
  });

  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final NotificationSeverity severity;
}

class NotificationProvider extends ChangeNotifier {
  final List<AppNotification> _items = [
    AppNotification(
      id: 'notif-1',
      title: 'Dock sync complete',
      message: 'Inbound manifest updated for bay 04.',
      createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
      severity: NotificationSeverity.info,
    ),
    AppNotification(
      id: 'notif-2',
      title: 'Thermal spike',
      message: 'Zone C ambient temperature exceeded target range.',
      createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      severity: NotificationSeverity.warning,
    ),
  ];

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _items.length;

  void push({
    required String title,
    required String message,
    NotificationSeverity severity = NotificationSeverity.info,
  }) {
    _items.insert(
      0,
      AppNotification(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        message: message,
        createdAt: DateTime.now(),
        severity: severity,
      ),
    );
    notifyListeners();
  }

  void dismiss(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
