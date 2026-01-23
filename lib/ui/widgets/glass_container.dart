import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:sqlbench/core/theme/app_theme.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final LinearGradient? gradient;
  final LinearGradient? borderGradient;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 16.0,
    this.blur = AppTheme.glassBlur,
    this.gradient,
    this.borderGradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: gradient ?? AppTheme.glassGradient,
        border: Border.all(
          width: 1.0,
          color: Colors.white.withOpacity(0.1),
        ), // Simple border for now, can enhance with gradient border painter if needed
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 16, spreadRadius: 4),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 0.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withOpacity(0.05), Colors.white.withOpacity(0.02)],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
