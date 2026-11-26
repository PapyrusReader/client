import 'package:flutter/foundation.dart';

class SidebarProvider extends ChangeNotifier {
  bool _isCollapsed = false;
  final _expandedSections = <String>{'/library'};

  bool get isCollapsed => _isCollapsed;
  double get sidebarWidth => _isCollapsed ? 72.0 : 280.0;
  bool isSectionExpanded(String path) => _expandedSections.contains(path);

  void toggleCollapsed() {
    _isCollapsed = !_isCollapsed;

    if (_isCollapsed) {
      _expandedSections.clear();
    }

    notifyListeners();
  }

  void toggleSection(String path) {
    if (_isCollapsed) {
      _isCollapsed = false;
    }

    if (!_expandedSections.remove(path)) {
      _expandedSections.add(path);
    }

    notifyListeners();
  }
}
