import 'package:flutter/material.dart';
import 'package:sqlbench/core/theme/app_theme.dart';

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool isLoading;

  const AppButton({
    required this.text,
    this.isLoading = false,
    this.onPressed,
    this.icon,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = color ?? AppTheme.primaryColor;
    final foregroundColor =
        backgroundColor.computeLuminance() > 0.45
            ? AppTheme.backgroundColor
            : Colors.white;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  backgroundColor == AppTheme.primaryColor
                      ? AppTheme.borderColor
                      : backgroundColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foregroundColor,
                  ),
                )
              else if (icon != null)
                Icon(icon, color: foregroundColor, size: 18),
              if (icon != null || isLoading) const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
