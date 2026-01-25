import 'package:flutter/material.dart';
import 'package:sqlbench/core/theme/app_theme.dart';

class AutocompleteOverlay extends StatelessWidget {
  final List<String> suggestions;
  final Function(String) onSelected;
  final int selectedIndex;

  const AutocompleteOverlay({
    super.key,
    required this.suggestions,
    required this.onSelected,
    this.selectedIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox();

    return Positioned(
      left: 16,
      top: 80, // Position below the query input area
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 16,
              spreadRadius: 4,
            ),
          ],
        ),
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
                  onTap: () => onSelected(suggestion),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: isSelected
                        ? BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          )
                        : null,
                    child: Row(
                      children: [
                        Icon(
                          _getIconForSuggestion(suggestion),
                          size: 16,
                          color: isSelected ? Colors.white : Colors.white70,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            suggestion,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
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
    // Check if it's a SQL keyword (uppercase)
    if (suggestion == suggestion.toUpperCase()) {
      return Icons.code;
    }
    // Otherwise it's a table name
    return Icons.table_chart_rounded;
  }
}
