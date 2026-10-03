import 'package:flutter/material.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_actions.dart';

/// Import uses the same footer actions as the other bottom sheets.
class BookImportSheetActions extends StatelessWidget {
  const BookImportSheetActions({super.key, required this.primary, this.secondary});

  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => BottomSheetActions(primary: primary, secondary: secondary);
}
