import 'package:flutter/foundation.dart';
import 'package:papyrus/models/collection_grid_size.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/providers/preferences_provider.dart';

/// Responsive grid density with an independent preference for each collection.
class CollectionGridDensity extends ChangeNotifier {
  CollectionGridDensity({required CollectionGridSection section, PreferencesProvider? preferences})
    : _section = section,
      _preferences = preferences,
      _width = preferences?.gridItemWidth(section) ?? CollectionGridSize.defaultWidth {
    _preferences?.addListener(_restoreWidth);
  }

  final PreferencesProvider? _preferences;
  final CollectionGridSection _section;
  double _width;

  double get width => _preferences?.gridItemWidth(_section) ?? _width;

  set width(double value) {
    if (_preferences case final preferences?) {
      preferences.setGridItemWidth(_section, value);
    } else {
      _updateWidth(CollectionGridSize.normalize(value));
    }
  }

  void _restoreWidth() => _updateWidth(_preferences!.gridItemWidth(_section));

  void _updateWidth(double width) {
    if (_width == width) {
      return;
    }

    _width = width;
    notifyListeners();
  }

  @override
  void dispose() {
    _preferences?.removeListener(_restoreWidth);
    super.dispose();
  }
}

abstract interface class CollectionViewControls implements Listenable {
  CollectionGridDensity get gridDensity;
  ValueNotifier<double> get gridAvailableWidth;
  LibraryViewMode get viewMode;
  void setViewMode(LibraryViewMode mode);
}
