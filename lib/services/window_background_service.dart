import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 窗口背景服务 - 管理 Fluent UI 窗口背景图片和模糊度
/// 注意：此功能独立于播放器背景，仅用于整个窗口的背景
class WindowBackgroundService extends ChangeNotifier {
  static final WindowBackgroundService _instance = WindowBackgroundService._internal();
  factory WindowBackgroundService() => _instance;
  WindowBackgroundService._internal() {
    _loadSettings();
  }

  // 是否启用窗口背景图片
  bool _enabled = false;
  
  // 背景图片路径
  String? _imagePath;
  
  // 模糊程度 (0-50)
  double _blurAmount = 20.0;
  
  // 不透明度 (0.0-1.0)
  double _opacity = 0.6;

  bool get enabled => _enabled;
  String? get imagePath => _imagePath;
  double get blurAmount => _blurAmount;
  double get opacity => _opacity;

  /// 从本地存储加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('window_background_enabled') ?? false;
      _imagePath = prefs.getString('window_background_image_path');
      _blurAmount = prefs.getDouble('window_background_blur') ?? 20.0;
      _opacity = prefs.getDouble('window_background_opacity') ?? 0.6;
      notifyListeners();
    } catch (e) {
      print('❌ [WindowBackgroundService] 加载设置失败: $e');
    }
  }

  /// 设置是否启用窗口背景
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('window_background_enabled', value);
    notifyListeners();
  }

  /// 设置背景图片
  Future<void> setImagePath(String? path) async {
    _imagePath = path;
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await prefs.setString('window_background_image_path', path);
    } else {
      await prefs.remove('window_background_image_path');
    }
    notifyListeners();
  }

  /// 设置模糊程度
  Future<void> setBlurAmount(double value) async {
    _blurAmount = value.clamp(0.0, 50.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window_background_blur', _blurAmount);
    notifyListeners();
  }

  /// 设置不透明度
  Future<void> setOpacity(double value) async {
    _opacity = value.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window_background_opacity', _opacity);
    notifyListeners();
  }

  /// 清除背景图片
  Future<void> clearImage() async {
    await setImagePath(null);
    await setEnabled(false);
  }

  /// 获取背景图片文件（如果存在）
  File? getImageFile() {
    if (_imagePath == null || _imagePath!.isEmpty) return null;
    final file = File(_imagePath!);
    return file.existsSync() ? file : null;
  }

  /// 检查是否有有效的背景图片
  bool get hasValidImage {
    return _imagePath != null && _imagePath!.isNotEmpty && getImageFile() != null;
  }
}
