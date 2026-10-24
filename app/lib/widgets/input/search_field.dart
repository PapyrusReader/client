import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// A reusable search field widget.
///
/// Provides a consistent search input with a search icon prefix,
/// optional clear button, and Material Design 3 styling.
///
/// ```dart
/// SearchField(
///   controller: _searchController,
///   hintText: 'Search notes...',
///   onChanged: (value) => setState(() => _query = value),
///   onClear: () => setState(() => _query = ''),
/// )
/// ```
class SearchField extends StatelessWidget {
  /// Controller for the text field.
  final TextEditingController controller;

  /// Placeholder text shown when the field is empty.
  final String hintText;

  /// Called when the text changes.
  final ValueChanged<String>? onChanged;

  final ValueChanged<String>? onSubmitted;

  /// Called when the clear button is pressed.
  ///
  /// If not provided but [onChanged] is, the clear button will call
  /// [onChanged] with an empty string.
  final VoidCallback? onClear;

  /// Minimum height of the search field, never below a 48-pixel touch target.
  final double? height;

  /// An optional action inside the field, after the clear button.
  final Widget? trailing;

  /// Creates a search field widget.
  const SearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.height,
    this.trailing,
  });

  /// Whether the search field has text content.
  bool get _hasContent => controller.text.isNotEmpty;

  void _handleClear() {
    controller.clear();

    if (onClear != null) {
      onClear!();
    } else {
      onChanged?.call('');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: (height ?? 48).clamp(48, double.infinity)),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: onSubmitted == null ? null : TextInputAction.search,
        decoration: InputDecoration(
          labelText: hintText,
          floatingLabelBehavior: FloatingLabelBehavior.never,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: trailing == null && !_hasContent
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_hasContent)
                      IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: _handleClear,
                      ),
                    ?trailing,
                  ],
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
          isDense: true,
        ),
      ),
    );
  }
}
