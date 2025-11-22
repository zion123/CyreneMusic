import 'package:flutter/foundation.dart';

/// 导航状态管理 Provider
/// 负责管理应用的导航状态，包括当前选中的页面索引和导航历史
class NavigationProvider with ChangeNotifier {
  int _currentIndex = 0;
  final List<int> _history = [0];

  /// 获取当前选中的页面索引
  int get currentIndex => _currentIndex;

  /// 获取导航历史记录
  List<int> get history => List.unmodifiable(_history);

  /// 导航到指定索引的页面
  /// 
  /// [index] 目标页面索引
  void navigateTo(int index) {
    if (_currentIndex != index) {
      _currentIndex = index;
      _history.add(index);
      notifyListeners();
    }
  }

  /// 检查是否可以返回上一页
  bool get canGoBack => _history.length > 1;

  /// 返回上一页
  void goBack() {
    if (canGoBack) {
      _history.removeLast();
      _currentIndex = _history.last;
      notifyListeners();
    }
  }

  /// 清空导航历史并重置到首页
  void reset() {
    _currentIndex = 0;
    _history.clear();
    _history.add(0);
    notifyListeners();
  }

  /// 获取历史记录长度
  int get historyLength => _history.length;
}
