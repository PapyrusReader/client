import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/app_page_bar.dart';

/// Header for the online book search experience.
class OnlineBooksHeader extends StatelessWidget {
  const OnlineBooksHeader({
    super.key,
    required this.controller,
    required this.autofocus,
    required this.isSearching,
    required this.onBack,
    required this.onSearch,
    this.compact = false,
  });

  final bool compact;
  final TextEditingController controller;
  final bool autofocus;
  final bool isSearching;
  final VoidCallback onBack;
  final ValueChanged<String> onSearch;

  void _submit() {
    final query = controller.text.trim();

    if (isSearching || query.isEmpty) {
      return;
    }

    onSearch(query);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useStackedLayout = constraints.maxWidth < Breakpoints.tablet;

        final backButton = Semantics(
          label: 'Back',
          button: true,
          child: IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack, tooltip: 'Back'),
        );

        final title = Text(
          'Online results',
          style: textTheme.headlineSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );

        if (useStackedLayout) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact)
                AppPageToolbar(leading: backButton, content: title)
              else ...[
                Row(
                  children: [
                    backButton,
                    const SizedBox(width: Spacing.sm),
                    Expanded(child: title),
                  ],
                ),
                const SizedBox(height: Spacing.sm),
              ],
              Padding(
                padding: compact ? EdgeInsets.symmetric(horizontal: AppPageToolbar.padding.left) : EdgeInsets.zero,
                child: _buildSearchField(),
              ),
            ],
          );
        }

        final search = Row(
          children: [
            Expanded(flex: 2, child: title),
            const SizedBox(width: Spacing.lg),
            Expanded(flex: 3, child: _buildSearchField()),
          ],
        );

        if (compact) {
          return AppPageToolbar(leading: backButton, content: search);
        }

        return Row(
          children: [
            backButton,
            const SizedBox(width: Spacing.sm),
            Expanded(child: search),
          ],
        );
      },
    );
  }

  Widget _buildSearchField() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final canSubmit = !isSearching && value.text.trim().isNotEmpty;

        return TextField(
          controller: controller,
          autofocus: autofocus,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: 'Search online books',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
            suffixIcon: Semantics(
              label: 'Search',
              button: true,
              child: IconButton(
                icon: const Icon(Icons.search),
                onPressed: canSubmit ? _submit : null,
                tooltip: 'Search',
              ),
            ),
          ),
        );
      },
    );
  }
}
