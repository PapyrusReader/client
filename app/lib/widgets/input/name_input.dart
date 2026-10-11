import 'package:flutter/material.dart';
import 'package:papyrus/widgets/input/validated_text_form_field.dart';

/// A reusable name input field with validation.
class NameInput extends StatelessWidget {
  /// Label text displayed for the input field
  final String labelText;

  /// Optional text controller for the input
  final TextEditingController? controller;

  /// Optional focus node for managing focus
  final FocusNode? focusNode;

  /// Callback when editing is complete
  final VoidCallback? onEditingComplete;

  /// Text input action for the keyboard
  final TextInputAction? textInputAction;

  const NameInput({
    super.key,
    this.controller,
    required this.labelText,
    this.focusNode,
    this.onEditingComplete,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValidatedTextFormField(
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: labelText,
        suffixIcon: Icon(Icons.person_outline, color: theme.colorScheme.onSurfaceVariant),
      ),
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.name,
      textInputAction: textInputAction ?? TextInputAction.next,
      onEditingComplete: onEditingComplete,
      textCapitalization: TextCapitalization.words,
      validator: _validateName,
    );
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }

    return null;
  }
}
