import 'package:flutter/material.dart';

/// Defers new errors until blur or submit, but clears resolved errors while editing.
class ValidatedTextFormField extends StatefulWidget {
  final InputDecoration decoration;
  final FormFieldValidator<String> validator;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onFieldSubmitted;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final Listenable? validationDependency;

  const ValidatedTextFormField({
    super.key,
    required this.decoration,
    required this.validator,
    this.controller,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.onEditingComplete,
    this.onFieldSubmitted,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.validationDependency,
  });

  @override
  State<ValidatedTextFormField> createState() => _ValidatedTextFormFieldState();
}

class _ValidatedTextFormFieldState extends State<ValidatedTextFormField> {
  final _fieldKey = GlobalKey<FormFieldState<String>>();
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    _controller.addListener(_clearResolvedError);
    widget.validationDependency?.addListener(_clearResolvedError);
  }

  @override
  void didUpdateWidget(covariant ValidatedTextFormField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      final value = _controller.value;
      _controller.removeListener(_clearResolvedError);

      if (oldWidget.controller == null) {
        _controller.dispose();
      }

      _controller = widget.controller ?? TextEditingController.fromValue(value);
      _controller.addListener(_clearResolvedError);
    }

    if (oldWidget.focusNode != widget.focusNode) {
      if (oldWidget.focusNode == null) {
        _focusNode.dispose();
      }

      _focusNode = widget.focusNode ?? FocusNode();
    }

    if (oldWidget.validationDependency != widget.validationDependency) {
      oldWidget.validationDependency?.removeListener(_clearResolvedError);
      widget.validationDependency?.addListener(_clearResolvedError);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_clearResolvedError);
    widget.validationDependency?.removeListener(_clearResolvedError);

    if (widget.controller == null) {
      _controller.dispose();
    }

    if (widget.focusNode == null) {
      _focusNode.dispose();
    }

    super.dispose();
  }

  void _clearResolvedError() {
    if (_fieldKey.currentState?.hasError != true) {
      return;
    }

    // Wait for TextFormField to receive controller/autofill changes first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final field = _fieldKey.currentState;

      if (field != null && field.hasError && field.isValid) {
        field.validate();
      }
    });
  }

  void _handleFocusChange(bool hasFocus) {
    if (!hasFocus && _controller.text.trim().isNotEmpty) {
      _fieldKey.currentState?.validate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onFocusChange: _handleFocusChange,
      child: TextFormField(
        key: _fieldKey,
        controller: _controller,
        focusNode: _focusNode,
        decoration: widget.decoration,
        validator: widget.validator,
        autovalidateMode: AutovalidateMode.disabled,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        textCapitalization: widget.textCapitalization,
        onEditingComplete: widget.onEditingComplete,
        onFieldSubmitted: widget.onFieldSubmitted,
        obscureText: widget.obscureText,
        autocorrect: widget.autocorrect,
        enableSuggestions: widget.enableSuggestions,
      ),
    );
  }
}

bool validateAndFocusForm(FormState form) {
  final invalidFields = form.validateGranularly();

  if (invalidFields.isEmpty) {
    return true;
  }

  final firstField = invalidFields.first;
  firstField.context.findAncestorStateOfType<_ValidatedTextFormFieldState>()?._focusNode.requestFocus();

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (firstField.mounted) {
      Scrollable.ensureVisible(firstField.context, alignment: 0.1);
    }
  });

  return false;
}
