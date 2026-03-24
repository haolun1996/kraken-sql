import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:sqlbench/core/theme/app_theme.dart';
import 'package:sqlbench/features/connection/data/connection_model.dart';
import 'package:sqlbench/features/connection/data/connection_provider.dart';
import 'package:sqlbench/ui/widgets/autocomplete_overlay.dart';
import 'package:sqlbench/ui/widgets/app_button.dart';

class QueryEditorScreen extends ConsumerStatefulWidget {
  final ConnectionModel connection;

  const QueryEditorScreen({required this.connection, super.key});

  @override
  ConsumerState<QueryEditorScreen> createState() => _QueryEditorScreenState();
}

class _QueryEditorScreenState extends ConsumerState<QueryEditorScreen> {
  final _queryController = TextEditingController();
  final _focusNode = FocusNode();
  MySQLConnection? _connection;
  bool _isExecuting = false;
  IResultSet? _result;
  String? _error;
  List<String> _databases = [];
  List<String> _tables = [];
  String? _selectedDatabase;

  List<String> _suggestions = [];
  int _selectedSuggestionIndex = 0;
  bool _showAutocomplete = false;

  static const List<String> _sqlKeywords = [
    'SELECT',
    'FROM',
    'WHERE',
    'JOIN',
    'LEFT JOIN',
    'RIGHT JOIN',
    'INNER JOIN',
    'OUTER JOIN',
    'ON',
    'GROUP BY',
    'ORDER BY',
    'HAVING',
    'LIMIT',
    'OFFSET',
    'INSERT',
    'INTO',
    'VALUES',
    'UPDATE',
    'SET',
    'DELETE',
    'CREATE',
    'TABLE',
    'ALTER',
    'DROP',
    'AND',
    'OR',
    'NOT',
    'IN',
    'LIKE',
    'BETWEEN',
    'AS',
    'DISTINCT',
    'COUNT',
    'SUM',
    'AVG',
    'MAX',
    'MIN',
    'ASC',
    'DESC',
    'NULL',
    'IS',
    'IS NOT',
  ];

  @override
  void initState() {
    super.initState();
    _connect();
    _queryController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _queryController.removeListener(_onTextChanged);
    _queryController.dispose();
    _focusNode.dispose();
    _connection?.close();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _queryController.text;
    final cursorPos = _queryController.selection.baseOffset;

    if (cursorPos < 0) return;

    final textBeforeCursor = text.substring(0, cursorPos);
    final words = textBeforeCursor.split(RegExp(r'[\s,()]'));
    final currentWord = words.isNotEmpty ? words.last : '';

    if (currentWord.isEmpty) {
      setState(() {
        _showAutocomplete = false;
        _suggestions = [];
      });
      return;
    }

    List<String> matches = [];

    matches.addAll(
      _sqlKeywords.where(
        (kw) => kw.toLowerCase().startsWith(currentWord.toLowerCase()),
      ),
    );

    if (_selectedDatabase != null && _tables.isNotEmpty) {
      matches.addAll(
        _tables.where(
          (table) => table.toLowerCase().startsWith(currentWord.toLowerCase()),
        ),
      );
    }

    setState(() {
      _suggestions = matches;
      _showAutocomplete = matches.isNotEmpty;
      _selectedSuggestionIndex = 0;
    });
  }

  void _insertSuggestion(String suggestion) {
    final text = _queryController.text;
    final cursorPos = _queryController.selection.baseOffset;

    if (cursorPos < 0) return;

    final textBeforeCursor = text.substring(0, cursorPos);
    final words = textBeforeCursor.split(RegExp(r'[\s,()]'));
    final currentWord = words.isNotEmpty ? words.last : '';

    final newCursorPos = cursorPos - currentWord.length + suggestion.length;
    final newText =
        text.substring(0, cursorPos - currentWord.length) +
        suggestion +
        text.substring(cursorPos);

    _queryController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );

    setState(() {
      _showAutocomplete = false;
      _suggestions = [];
    });

    _focusNode.requestFocus();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter &&
          HardwareKeyboard.instance.isMetaPressed) {
        _executeQuery();
        return true;
      }
    }

    if (!_showAutocomplete) return false;

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedSuggestionIndex =
              (_selectedSuggestionIndex + 1) % _suggestions.length;
        });
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedSuggestionIndex =
              (_selectedSuggestionIndex - 1 + _suggestions.length) %
              _suggestions.length;
        });
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        if (_suggestions.isNotEmpty) {
          _insertSuggestion(_suggestions[_selectedSuggestionIndex]);
          return true;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() {
          _showAutocomplete = false;
          _suggestions = [];
        });
        return true;
      }
    }
    return false;
  }

  Future<void> _connect() async {
    try {
      _connection = await MySQLService.connect(widget.connection);
      final dbs = await MySQLService.getDatabases(_connection!);
      setState(() {
        _databases = dbs
            .where(
              (db) =>
                  db != 'information_schema' &&
                  db != 'performance_schema' &&
                  db != 'mysql' &&
                  db != 'sys',
            )
            .toList();
      });

      if (widget.connection.database != null &&
          widget.connection.database!.isNotEmpty) {
        await _loadTables(widget.connection.database!);
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to connect: $e';
      });
    }
  }

  Future<void> _loadTables(String database) async {
    if (_connection == null) return;
    try {
      await MySQLService.selectDatabase(_connection!, database);
      final tables = await MySQLService.getTables(_connection!, database);
      setState(() {
        _selectedDatabase = database;
        _tables = tables;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load tables: $e';
      });
    }
  }

  Future<void> _executeQuery() async {
    if (_connection == null || _queryController.text.isEmpty) return;

    setState(() {
      _isExecuting = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await MySQLService.executeQuery(
        _connection!,
        _queryController.text,
      );
      setState(() {
        _result = result;
        _isExecuting = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Query error: $e';
        _isExecuting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 260,
          height: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.sidebarColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Databases',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Double click to load tables',
                style: TextStyle(color: AppTheme.mutedTextColor, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Expanded(
                child:
                    _databases.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                          itemCount: _databases.length,
                          itemBuilder: (context, index) {
                            final db = _databases[index];
                            return _DatabaseItem(
                              name: db,
                              isSelected: _selectedDatabase == db,
                              onDoubleTap: () => _loadTables(db),
                            );
                          },
                        ),
              ),
              if (_selectedDatabase != null) ...[
                const SizedBox(height: 12),
                const Divider(color: AppTheme.borderColor),
                const SizedBox(height: 12),
                Text(
                  'Tables',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppTheme.mutedTextColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: _tables.length,
                    itemBuilder: (context, index) {
                      final table = _tables[index];
                      return _TableItem(
                        name: table,
                        onTap: () {
                          _queryController.text =
                              'SELECT * FROM `$_selectedDatabase`.`$table` LIMIT 100;';
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              Stack(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: AppTheme.panelDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.connection.name,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${widget.connection.host}:${widget.connection.port}',
                                  style: const TextStyle(
                                    color: AppTheme.mutedTextColor,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            AppButton(
                              text: 'Execute',
                              icon: Icons.play_arrow_rounded,
                              onPressed: _executeQuery,
                              isLoading: _isExecuting,
                              color: AppTheme.secondaryColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          constraints: const BoxConstraints(minHeight: 220),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.borderColor),
                          ),
                          child: Focus(
                            onKeyEvent: (node, event) {
                              return _handleKeyEvent(event)
                                  ? KeyEventResult.handled
                                  : KeyEventResult.ignored;
                            },
                            child: TextField(
                              controller: _queryController,
                              focusNode: _focusNode,
                              maxLines: null,
                              style: const TextStyle(
                                color: AppTheme.primaryColor,
                                fontFamily: 'monospace',
                                fontSize: 14,
                                height: 1.45,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'SELECT * FROM users;',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_showAutocomplete)
                    AutocompleteOverlay(
                      suggestions: _suggestions,
                      selectedIndex: _selectedSuggestionIndex,
                      onSelected: _insertSuggestion,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: AppTheme.panelDecoration(),
                  child:
                      _error != null
                          ? Center(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: AppTheme.errorColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                          : _result == null
                          ? const Center(
                            child: Text(
                              'Execute a query to see results',
                              style: TextStyle(color: AppTheme.mutedTextColor),
                            ),
                          )
                          : _buildResultsTable(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultsTable() {
    if (_result == null) return const SizedBox();

    final columns = _result!.cols.map((col) => col.name).toList();
    final rows = _result!.rows;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: AppTheme.borderColor,
          ),
          child: DataTable(
            columns:
                columns
                    .map((col) => DataColumn(label: Text(col)))
                    .toList(),
            rows:
                rows
                    .map(
                      (row) => DataRow(
                        cells:
                            row
                                .typedAssoc()
                                .values
                                .map(
                                  (value) => DataCell(
                                    Text(
                                      value?.toString() ?? 'NULL',
                                      style: const TextStyle(
                                        color: AppTheme.mutedTextColor,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    )
                    .toList(),
          ),
        ),
      ),
    );
  }
}

class _DatabaseItem extends StatelessWidget {
  final String name;
  final bool isSelected;
  final VoidCallback onDoubleTap;

  const _DatabaseItem({
    required this.name,
    required this.isSelected,
    required this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected ? const Color(0xFF1B232C) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onDoubleTap: onDoubleTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration:
                isSelected
                    ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderColor),
                    )
                    : null,
            child: Row(
              children: [
                Icon(
                  Icons.storage_rounded,
                  color:
                      isSelected
                          ? AppTheme.secondaryColor
                          : AppTheme.mutedTextColor,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color:
                          isSelected
                              ? AppTheme.primaryColor
                              : AppTheme.mutedTextColor,
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TableItem extends StatelessWidget {
  final String name;
  final VoidCallback onTap;

  const _TableItem({required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(
                Icons.table_chart_rounded,
                color: AppTheme.mutedTextColor,
                size: 14,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: AppTheme.mutedTextColor,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
