import 'package:flutter/material.dart';
import 'package:papyrus/widgets/input/validated_text_form_field.dart';

/// A reusable email input field with validation.
class EmailInput extends StatelessWidget {
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

  const EmailInput({
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
        suffixIcon: Icon(Icons.email_outlined, color: theme.colorScheme.onSurfaceVariant),
      ),
      controller: controller,
      focusNode: focusNode,
      autofillHints: const [AutofillHints.email],
      keyboardType: TextInputType.emailAddress,
      textInputAction: textInputAction ?? TextInputAction.next,
      onEditingComplete: onEditingComplete,
      autocorrect: false,
      enableSuggestions: false,
      validator: _validateEmail,
    );
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'This field is required';
    }

    if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(value)) {
      return 'Not a valid email';
    }

    return null;
  }
}
