import 'package:flutter/material.dart';
import 'app_motion.dart';
import 'instant_outline_input_border.dart';
import 'color_schemes.g.dart';
import 'design_tokens.dart';

/// Application theme configurations.
/// Provides ThemeData for light, dark, and e-ink display modes.
class AppTheme {
  AppTheme._();

  static const dyslexiaFontFamily = 'OpenDyslexic';

  static ThemeData withTypography(ThemeData theme, {bool dyslexiaFont = false, bool boldText = false}) {
    if (!dyslexiaFont && !boldText) {
      return theme;
    }

    TextStyle? fontStyle(TextStyle? style) => style?.copyWith(
      fontFamily: dyslexiaFont ? dyslexiaFontFamily : null,
      fontWeight: boldText && (style.fontWeight ?? FontWeight.normal).value < FontWeight.bold.value
          ? FontWeight.bold
          : null,
    );

    TextTheme textTheme(TextTheme source) => TextTheme(
      displayLarge: fontStyle(source.displayLarge),
      displayMedium: fontStyle(source.displayMedium),
      displaySmall: fontStyle(source.displaySmall),
      headlineLarge: fontStyle(source.headlineLarge),
      headlineMedium: fontStyle(source.headlineMedium),
      headlineSmall: fontStyle(source.headlineSmall),
      titleLarge: fontStyle(source.titleLarge),
      titleMedium: fontStyle(source.titleMedium),
      titleSmall: fontStyle(source.titleSmall),
      bodyLarge: fontStyle(source.bodyLarge),
      bodyMedium: fontStyle(source.bodyMedium),
      bodySmall: fontStyle(source.bodySmall),
      labelLarge: fontStyle(source.labelLarge),
      labelMedium: fontStyle(source.labelMedium),
      labelSmall: fontStyle(source.labelSmall),
    );

    ButtonStyle? buttonStyle(ButtonStyle? style) {
      final textStyle = style?.textStyle;

      if (textStyle == null) {
        return style;
      }

      return style!.copyWith(
        textStyle: WidgetStateProperty.resolveWith((states) => fontStyle(textStyle.resolve(states))),
      );
    }

    final navigationLabelStyle = theme.navigationBarTheme.labelTextStyle;

    return theme.copyWith(
      textTheme: textTheme(theme.textTheme),
      primaryTextTheme: textTheme(theme.primaryTextTheme),
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: fontStyle(theme.appBarTheme.titleTextStyle),
        toolbarTextStyle: fontStyle(theme.appBarTheme.toolbarTextStyle),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle(theme.elevatedButtonTheme.style)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle(theme.outlinedButtonTheme.style)),
      textButtonTheme: TextButtonThemeData(style: buttonStyle(theme.textButtonTheme.style)),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        labelStyle: fontStyle(theme.inputDecorationTheme.labelStyle),
        floatingLabelStyle: fontStyle(theme.inputDecorationTheme.floatingLabelStyle),
        hintStyle: fontStyle(theme.inputDecorationTheme.hintStyle),
      ),
      navigationBarTheme: theme.navigationBarTheme.copyWith(
        labelTextStyle: navigationLabelStyle == null
            ? null
            : WidgetStateProperty.resolveWith((states) => fontStyle(navigationLabelStyle.resolve(states))),
      ),
      bottomNavigationBarTheme: theme.bottomNavigationBarTheme.copyWith(
        selectedLabelStyle: fontStyle(theme.bottomNavigationBarTheme.selectedLabelStyle),
        unselectedLabelStyle: fontStyle(theme.bottomNavigationBarTheme.unselectedLabelStyle),
      ),
      chipTheme: theme.chipTheme.copyWith(
        labelStyle: fontStyle(theme.chipTheme.labelStyle),
        secondaryLabelStyle: fontStyle(theme.chipTheme.secondaryLabelStyle),
      ),
      snackBarTheme: theme.snackBarTheme.copyWith(contentTextStyle: fontStyle(theme.snackBarTheme.contentTextStyle)),
      popupMenuTheme: theme.popupMenuTheme.copyWith(textStyle: fontStyle(theme.popupMenuTheme.textStyle)),
    );
  }

  static ThemeData get light => _standard(lightColorScheme);
  static ThemeData get dark => _standard(darkColorScheme);

  static ThemeData get highContrastLight => _highContrast(Brightness.light);
  static ThemeData get highContrastDark => _highContrast(Brightness.dark);

  static ThemeData _highContrast(Brightness brightness) => _standard(
    ColorScheme.fromSeed(seedColor: lightColorScheme.primary, brightness: brightness, contrastLevel: 1),
  );

  static ThemeData _standard(ColorScheme colors) => ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    textTheme: _textTheme,
    elevatedButtonTheme: _elevatedButtonTheme(colors),
    outlinedButtonTheme: _outlinedButtonTheme(colors),
    textButtonTheme: _textButtonTheme(colors),
    switchTheme: _switchTheme,
    inputDecorationTheme: _inputDecorationTheme(colors),
    cardTheme: _cardTheme(colors),
    appBarTheme: _appBarTheme(colors),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: colors.surface),
    dialogTheme: const DialogThemeData(
      constraints: BoxConstraints(minWidth: 280, maxWidth: ComponentSizes.dialogMaxWidth),
    ),
    bottomNavigationBarTheme: _bottomNavTheme(colors),
    dividerTheme: _dividerTheme(colors),
    snackBarTheme: _snackBarTheme(colors),
    popupMenuTheme: _popupMenuTheme(colors),
  );

  static ThemeData get eink => ThemeData(
    useMaterial3: true,
    colorScheme: einkColorScheme,
    extensions: const [AppMotion(reduceAnimations: true)],
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: InstantPageTransitionsBuilder(),
        TargetPlatform.iOS: InstantPageTransitionsBuilder(),
        TargetPlatform.macOS: InstantPageTransitionsBuilder(),
        TargetPlatform.windows: InstantPageTransitionsBuilder(),
        TargetPlatform.linux: InstantPageTransitionsBuilder(),
        TargetPlatform.fuchsia: InstantPageTransitionsBuilder(),
      },
    ),
    textTheme: _einkTextTheme,
    // Component themes - e-ink specific
    elevatedButtonTheme: _einkElevatedButtonTheme(),
    outlinedButtonTheme: _einkOutlinedButtonTheme(),
    textButtonTheme: _einkTextButtonTheme(),
    switchTheme: _switchTheme,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: EinkColors.black,
        foregroundColor: EinkColors.white,
        disabledBackgroundColor: EinkColors.lightGray,
        disabledForegroundColor: EinkColors.darkGray,
        shape: const RoundedRectangleBorder(),
        animationDuration: Duration.zero,
      ),
    ),
    iconButtonTheme: const IconButtonThemeData(style: ButtonStyle(animationDuration: Duration.zero)),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: EinkColors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: EinkColors.black,
      indicatorShape: const RoundedRectangleBorder(),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? EinkColors.white : EinkColors.black),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: EinkColors.black,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: EinkColors.white,
      selectedColor: EinkColors.lightGray,
      secondarySelectedColor: EinkColors.lightGray,
      labelStyle: TextStyle(color: EinkColors.black),
      secondaryLabelStyle: TextStyle(color: EinkColors.black),
      checkmarkColor: EinkColors.black,
      side: BorderSide(color: EinkColors.black, width: BorderWidths.einkDefault),
      elevation: 0,
      pressElevation: 0,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: EinkColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: EinkColors.black, width: BorderWidths.einkDefault),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: EinkColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: EinkColors.black, width: BorderWidths.einkDefault),
      ),
    ),
    dialogTheme: const DialogThemeData(
      constraints: BoxConstraints(minWidth: 280, maxWidth: ComponentSizes.dialogMaxWidth),
      backgroundColor: EinkColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: EinkColors.black, width: BorderWidths.einkDefault),
      ),
    ),
    inputDecorationTheme: _einkInputDecorationTheme(),
    cardTheme: _einkCardTheme(),
    appBarTheme: _einkAppBarTheme(),
    bottomNavigationBarTheme: _einkBottomNavTheme(),
    dividerTheme: _einkDividerTheme(),
    snackBarTheme: _einkSnackBarTheme(),
    // Disable animations
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
  );

  static const TextTheme _textTheme = TextTheme(
    displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.w400, letterSpacing: -0.25),
    displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w400, letterSpacing: 0),
    displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w400, letterSpacing: 0),
    headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w400, letterSpacing: 0),
    headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w400, letterSpacing: 0),
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w400, letterSpacing: 0),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w400, letterSpacing: 0),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0.15),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.5),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.25),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.4),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
  );

  static TextTheme get _einkTextTheme => _textTheme
      .copyWith(
        bodyMedium: _textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w500),
        bodySmall: _textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w500),
        labelMedium: _textTheme.labelMedium!.copyWith(fontWeight: FontWeight.w600),
        labelSmall: _textTheme.labelSmall!.copyWith(fontWeight: FontWeight.w600),
      )
      .apply(bodyColor: EinkColors.black, displayColor: EinkColors.black);

  static ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme colors) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(ComponentSizes.buttonHeightMobile),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.buttonPaddingHorizontal,
          vertical: Spacing.buttonPaddingVertical,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        elevation: AppElevation.level1,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme colors) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(ComponentSizes.buttonHeightMobile),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.buttonPaddingHorizontal,
          vertical: Spacing.buttonPaddingVertical,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        side: BorderSide(color: colors.outline, width: BorderWidths.thin),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    );
  }

  static TextButtonThemeData _textButtonTheme(ColorScheme colors) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    );
  }

  static InputDecorationTheme _inputDecorationTheme(ColorScheme colors) {
    return InputDecorationTheme(
      filled: false,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: BorderSide(color: colors.outline, width: BorderWidths.inputDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: BorderSide(color: colors.outline, width: BorderWidths.inputDefault),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: BorderSide(color: colors.primary, width: BorderWidths.inputFocused),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: BorderSide(color: colors.error, width: BorderWidths.inputError),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: BorderSide(color: colors.error, width: BorderWidths.inputError),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: TextStyle(color: colors.onSurfaceVariant),
      hintStyle: TextStyle(color: colors.onSurfaceVariant),
    );
  }

  static CardThemeData _cardTheme(ColorScheme colors) {
    return CardThemeData(
      elevation: AppElevation.level1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      margin: const EdgeInsets.all(Spacing.sm),
    );
  }

  static AppBarTheme _appBarTheme(ColorScheme colors) {
    return AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: AppElevation.level1,
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      titleTextStyle: TextStyle(color: colors.onSurface, fontSize: 22, fontWeight: FontWeight.w400),
    );
  }

  static BottomNavigationBarThemeData _bottomNavTheme(ColorScheme colors) {
    return BottomNavigationBarThemeData(
      backgroundColor: colors.surface,
      selectedItemColor: colors.primary,
      unselectedItemColor: colors.onSurfaceVariant,
      type: BottomNavigationBarType.fixed,
      elevation: AppElevation.level2,
    );
  }

  static final _switchTheme = SwitchThemeData(
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered) &&
          !states.contains(WidgetState.focused) &&
          !states.contains(WidgetState.pressed)) {
        return Colors.transparent;
      }

      return null;
    }),
  );

  static DividerThemeData _dividerTheme(ColorScheme colors) {
    return DividerThemeData(color: colors.outlineVariant, thickness: 1, space: Spacing.md);
  }

  static SnackBarThemeData _snackBarTheme(ColorScheme colors) {
    return SnackBarThemeData(
      backgroundColor: colors.inverseSurface,
      contentTextStyle: TextStyle(color: colors.onInverseSurface),
      actionTextColor: colors.inversePrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      behavior: SnackBarBehavior.floating,
    );
  }

  static PopupMenuThemeData _popupMenuTheme(ColorScheme colors) {
    return PopupMenuThemeData(
      elevation: AppElevation.level3,
      color: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: colors.outlineVariant, width: BorderWidths.thin),
      ),
      textStyle: TextStyle(color: colors.onSurface),
      mouseCursor: WidgetStateMouseCursor.clickable,
    );
  }

  static ElevatedButtonThemeData _einkElevatedButtonTheme() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(ComponentSizes.buttonHeightMobile),
        animationDuration: Duration.zero,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.buttonPaddingHorizontal,
          vertical: Spacing.buttonPaddingVertical,
        ),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        elevation: 0,
        backgroundColor: EinkColors.black,
        foregroundColor: EinkColors.white,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  static OutlinedButtonThemeData _einkOutlinedButtonTheme() {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(ComponentSizes.buttonHeightMobile),
        animationDuration: Duration.zero,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.buttonPaddingHorizontal,
          vertical: Spacing.buttonPaddingVertical,
        ),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        side: const BorderSide(color: EinkColors.black, width: BorderWidths.einkDefault),
        backgroundColor: EinkColors.white,
        foregroundColor: EinkColors.black,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  static TextButtonThemeData _einkTextButtonTheme() {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        animationDuration: Duration.zero,
        foregroundColor: EinkColors.black,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  static InputDecorationTheme _einkInputDecorationTheme() {
    return const InputDecorationTheme(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      floatingLabelStyle: TextStyle(color: EinkColors.black, fontSize: 16, fontWeight: FontWeight.w700),
      hintFadeDuration: Duration.zero,
      hoverColor: Colors.transparent,
      filled: true,
      fillColor: EinkColors.container,
      border: InstantOutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: EinkColors.black, width: BorderWidths.einkDefault),
      ),
      enabledBorder: InstantOutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: EinkColors.black, width: BorderWidths.einkDefault),
      ),
      focusedBorder: InstantOutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: EinkColors.black, width: BorderWidths.einkFocused),
      ),
      errorBorder: InstantOutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: EinkColors.black, width: BorderWidths.einkError),
      ),
      focusedErrorBorder: InstantOutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: EinkColors.black, width: BorderWidths.einkError),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: TextStyle(color: EinkColors.black, fontSize: 16, fontWeight: FontWeight.w700),
      hintStyle: TextStyle(color: EinkColors.darkGray),
    );
  }

  static CardThemeData _einkCardTheme() {
    return const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: EinkColors.black, width: BorderWidths.einkDefault),
      ),
      margin: EdgeInsets.all(Spacing.sm),
    );
  }

  static AppBarTheme _einkAppBarTheme() {
    return const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: EinkColors.white,
      foregroundColor: EinkColors.black,
      titleTextStyle: TextStyle(color: EinkColors.black, fontSize: 22, fontWeight: FontWeight.w700),
      shape: Border(
        bottom: BorderSide(color: EinkColors.black, width: BorderWidths.einkDefault),
      ),
    );
  }

  static BottomNavigationBarThemeData _einkBottomNavTheme() {
    return const BottomNavigationBarThemeData(
      backgroundColor: EinkColors.white,
      selectedItemColor: EinkColors.black,
      unselectedItemColor: EinkColors.darkGray,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    );
  }

  static DividerThemeData _einkDividerTheme() {
    return const DividerThemeData(color: EinkColors.black, thickness: 2, space: Spacing.md);
  }

  static SnackBarThemeData _einkSnackBarTheme() {
    return const SnackBarThemeData(
      backgroundColor: EinkColors.black,
      contentTextStyle: TextStyle(color: EinkColors.white),
      actionTextColor: EinkColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      behavior: SnackBarBehavior.floating,
    );
  }
}
