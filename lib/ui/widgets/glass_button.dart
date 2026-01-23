import 'package:flutter/material.dart';
import 'package:sqlbench/core/theme/app_theme.dart';
import 'package:sqlbench/ui/widgets/glass_container.dart';

class GlassButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool isLoading;

  const GlassButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (color ?? AppTheme.primaryColor).withOpacity(0.3),
            (color ?? AppTheme.primaryColor).withOpacity(0.1),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            else if (icon != null)
              Icon(icon, color: Colors.white, size: 18),
            if (icon != null || isLoading) const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
