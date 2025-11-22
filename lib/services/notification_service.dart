import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'developer_mode_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Android initialization settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Linux initialization settings
    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    final String? windowsIconPath =
        Platform.isWindows ? _resolveWindowsIconPath() : null;

    if (Platform.isWindows && windowsIconPath == null) {
      DeveloperModeService().addLog('⚠️ 未找到 Windows 通知图标，将使用空白图标');
    }

    final WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
      appName: 'Cyrene Music',
      appUserModelId: 'CyreneMusic.CyreneMusic.Desktop',
      guid: 'f5f2bb3e-5ca5-4cde-b61e-1464f93a4a85',
      iconPath: windowsIconPath,
    );

    // Darwin (iOS/macOS) initialization settings
    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
      linux: initializationSettingsLinux,
      windows: initializationSettingsWindows,
    );

    try {
      await _flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse details) {
          print('🔔 [NotificationService] Notification clicked: ${details.payload}');
        },
      );
      _isInitialized = true;
      DeveloperModeService().addLog('🔔 通知服务已初始化');
      
      // 针对 Windows 平台请求权限（虽然不一定必须，但有助于诊断）
      if (Platform.isWindows) {
        /* Windows 实现通常不需要显式请求权限，但我们可以尝试检查 */
        DeveloperModeService().addLog('🪟 Windows 平台通知初始化完成');
      }
    } catch (e) {
      DeveloperModeService().addLog('❌ 通知服务初始化失败: $e');
    }
  }

  String? _resolveWindowsIconPath() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final candidates = <String>[
        p.join(
          exeDir.path,
          'data',
          'flutter_assets',
          'assets',
          'icons',
          'tray_icon.ico',
        ),
        p.join(Directory.current.path, 'assets', 'icons', 'tray_icon.ico'),
      ];

      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          return candidate;
        }
      }
    } catch (e) {
      DeveloperModeService().addLog('⚠️ 解析 Windows 通知图标失败: $e');
      debugPrint('Failed to resolve Windows notification icon path: $e');
    }
    return null;
  }

  /// Send a simple notification
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'cyrene_music_channel',
      'Cyrene Music Notifications',
      channelDescription: 'Notifications for Cyrene Music',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    const WindowsNotificationDetails windowsNotificationDetails =
        WindowsNotificationDetails();

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      windows: windowsNotificationDetails,
    );

    try {
      DeveloperModeService().addLog('🔔 尝试发送通知: $title');
      await _flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
      DeveloperModeService().addLog('✅ 通知发送请求已发出');
    } catch (e) {
      DeveloperModeService().addLog('❌ 发送通知失败: $e');
    }
  }
}
