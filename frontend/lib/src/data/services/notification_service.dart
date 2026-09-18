import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/services/forgetting_curve.dart';

class NotificationService {
  NotificationService({required QuestionRepository questionRepository})
      : _questionRepository = questionRepository;

  final QuestionRepository _questionRepository;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);
  }

  Future<void> checkAndNotify() async {
    await init();
    final all = await _questionRepository.listAll();
    // 按遗忘曲线只统计"到期"的题，而非所有未掌握
    final dueCount = all.where(isDue).length;

    if (dueCount > 0) {
      await _plugin.show(
        0,
        '错题本复习提醒',
        '你有 $dueCount 道错题待复习，快来巩固吧！',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'review_reminder',
            '复习提醒',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    }
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
