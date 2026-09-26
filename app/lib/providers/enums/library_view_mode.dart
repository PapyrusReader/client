enum LibraryViewMode { grid, list }

extension LibraryViewModeExtension on LibraryViewMode {
  String get label {
    switch (this) {
      case LibraryViewMode.grid:
        return 'Grid';
      case LibraryViewMode.list:
        return 'List';
    }
  }
}
