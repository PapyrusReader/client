import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Branding element with logo and app name.
class AuthBranding extends StatelessWidget {
  final Color? textColor;
  final Color? iconOutlineColor;
  final double iconSize;
  final double fontSize;
  final double iconOutlineWidth;
  final Color? shadowColor;
  final Offset shadowOffset;
  final double shadowBlurRadius;
  final Color? textShadowColor;
  final Offset textShadowOffset;
  final double textShadowBlurRadius;
  final Axis direction;
  final double spacing;

  const AuthBranding({
    super.key,
    this.textColor,
    this.iconOutlineColor,
    this.iconSize = 56,
    this.fontSize = 36,
    this.iconOutlineWidth = 0,
    this.shadowColor,
    this.shadowOffset = const Offset(0, 1),
    this.shadowBlurRadius = 4,
    this.textShadowColor,
    this.textShadowOffset = const Offset(0, 1),
    this.textShadowBlurRadius = 3,
    this.direction = Axis.horizontal,
    this.spacing = 12,
  });

  const AuthBranding.hero({
    Key? key,
    Color textColor = Colors.white,
    double iconSize = 70,
    double fontSize = 40,
    Axis direction = Axis.horizontal,
    double spacing = 12,
  }) : this(
         key: key,
         textColor: textColor,
         iconSize: iconSize,
         fontSize: fontSize,
         direction: direction,
         spacing: spacing,
         iconOutlineColor: const Color(0x998F89FF),
         iconOutlineWidth: 3,
         shadowColor: const Color(0x40000000),
         textShadowColor: const Color(0x59000000),
         textShadowOffset: const Offset(0, 2),
         textShadowBlurRadius: 6,
       );

  @override
  Widget build(BuildContext context) {
    final foregroundColor = textColor ?? Theme.of(context).colorScheme.onSurface;

    return Flex(
      direction: direction,
      mainAxisSize: MainAxisSize.min,
      children: [
        _LogoIcon(
          size: iconSize,
          outlineColor: iconOutlineColor,
          outlineWidth: iconOutlineWidth,
          shadowColor: shadowColor,
          shadowOffset: shadowOffset,
          shadowBlurRadius: shadowBlurRadius,
        ),
        SizedBox(width: direction == Axis.horizontal ? spacing : 0, height: direction == Axis.vertical ? spacing : 0),
        Text(
          'Papyrus',
          style: TextStyle(
            fontFamily: 'MadimiOne',
            fontSize: fontSize,
            height: direction == Axis.vertical ? 1 : null,
            fontWeight: FontWeight.normal,
            color: foregroundColor,
            letterSpacing: 0,
            shadows: textShadowColor == null
                ? null
                : [Shadow(color: textShadowColor!, offset: textShadowOffset, blurRadius: textShadowBlurRadius)],
          ),
        ),
      ],
    );
  }
}

class _LogoIcon extends StatelessWidget {
  final double size;
  final Color? outlineColor;
  final double outlineWidth;
  final Color? shadowColor;
  final Offset shadowOffset;
  final double shadowBlurRadius;

  const _LogoIcon({
    required this.size,
    this.outlineColor,
    required this.outlineWidth,
    this.shadowColor,
    required this.shadowOffset,
    required this.shadowBlurRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (outlineColor == null && shadowColor == null) {
      return SvgPicture.asset('assets/images/logo-icon-light.svg', width: size, height: size);
    }

    final outlineSize = size + outlineWidth * 2;

    return SizedBox(
      width: outlineSize,
      height: outlineSize,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (shadowColor != null)
            Transform.translate(
              offset: shadowOffset,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: shadowBlurRadius / 2, sigmaY: shadowBlurRadius / 2),
                child: SvgPicture.asset(
                  'assets/images/logo-icon-light.svg',
                  width: outlineSize,
                  height: outlineSize,
                  colorFilter: ColorFilter.mode(shadowColor!, BlendMode.srcIn),
                ),
              ),
            ),
          if (outlineColor != null && outlineWidth > 0)
            SvgPicture.asset(
              'assets/images/logo-icon-light.svg',
              width: outlineSize,
              height: outlineSize,
              colorFilter: ColorFilter.mode(outlineColor!, BlendMode.srcIn),
            ),
          SvgPicture.asset('assets/images/logo-icon-light.svg', width: size, height: size),
        ],
      ),
    );
  }
}
