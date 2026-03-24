import 'package:flutter/material.dart';
import 'package:sqlbench/core/theme/app_theme.dart';

class AutocompleteOverlay extends StatelessWidget {
  final List<String> suggestions;
  final Function(String) onSelected;
  final int selectedIndex;

  const AutocompleteOverlay({
    required this.suggestions,
    required this.onSelected,
    this.selectedIndex = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox();

    return Positioned(
      left: 16,
      top: 80,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(8),
        decoration: AppTheme.panelDecoration(elevated: true),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...List.generate(
              suggestions.length > 10 ? 10 : suggestions.length,
              (index) {
                final suggestion = suggestions[index];
                final isSelected = index == selectedIndex;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelected(suggestion),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration:
                        isSelected
                            ? BoxDecoration(
                              color: const Color(0xFF212A34),
                              borderRadius: BorderRadius.circular(12),
                            )
                            : null,
                    child: Row(
                      children: [
                        Icon(
                          _getIconForSuggestion(suggestion),
                          size: 16,
                          color:
                              isSelected
                                  ? AppTheme.secondaryColor
                                  : AppTheme.mutedTextColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            suggestion,
                            style: TextStyle(
                              color:
                                  isSelected
                                      ? AppTheme.primaryColor
                                      : AppTheme.mutedTextColor,
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForSuggestion(String suggestion) {
    if (suggestion == suggestion.toUpperCase()) {
      return Icons.code_rounded;
    }
    return Icons.table_chart_rounded;
  }
}
