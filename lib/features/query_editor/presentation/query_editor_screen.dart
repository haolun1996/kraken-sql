import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:sqlbench/core/theme/app_theme.dart';
import 'package:sqlbench/features/connection/data/connection_model.dart';
import 'package:sqlbench/features/connection/data/connection_provider.dart';
import 'package:sqlbench/features/query_editor/data/query_workspace_store.dart';
import 'package:sqlbench/features/query_editor/data/table_models.dart';
import 'package:sqlbench/ui/widgets/app_button.dart';
import 'package:sqlbench/ui/widgets/autocomplete_overlay.dart';

class QueryEditorScreen extends ConsumerStatefulWidget {
  final ConnectionModel connection;

  const QueryEditorScreen({required this.connection, super.key});

  @override
  ConsumerState<QueryEditorScreen> createState() => _QueryEditorScreenState();
}

class _QueryEditorScreenState extends ConsumerState<QueryEditorScreen> {
  final _queryController = TextEditingController();
  final _queryFocusNode = FocusNode();
  final _filterController = TextEditingController();

  MySQLConnection? _connection;

  bool _isConnecting = true;
  bool _isExecuting = false;
  bool _isLoadingDatabases = false;
  bool _isLoadingMetadata = false;
  bool _isLoadingTablePage = false;
  bool _isApplyingChanges = false;

  String? _connectionError;
  String? _queryError;
  String? _tableError;

  IResultSet? _queryResult;
  WorkspaceMode _workspaceMode = WorkspaceMode.query;

  List<String> _databases = [];
  String? _selectedDatabase;
  final Map<String, List<TableSummary>> _tablesByDatabase = {};
  final Set<String> _expandedDatabases = {};
  final Set<String> _loadingTableDatabases = {};
  TableSelection? _selection;
  TableSummary? _selectedTableSummary;

  List<TableColumnInfo> _tableColumns = [];
  List<TableKeyInfo> _tableKeys = [];
  TablePageData? _tablePage;
  TablePageRequest _pageRequest = const TablePageRequest();

  List<String> _suggestions = [];
  int _selectedSuggestionIndex = 0;
  bool _showAutocomplete = false;

  final Map<String, PendingRowChange> _pendingUpdates = {};
  final Map<String, PendingRowChange> _pendingInserts = {};
  final Set<String> _pendingDeletes = {};
  final Set<String> _selectedRowIds = {};
  int _newRowCounter = 0;

  List<QueryHistoryItem> _queryHistory = [];
  List<QuerySnippet> _querySnippets = [];

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
    _queryController.addListener(_onTextChanged);
    _connect();
    _loadPersistedWorkspace();
  }

  @override
  void dispose() {
    _queryController.removeListener(_onTextChanged);
    _queryController.dispose();
    _queryFocusNode.dispose();
    _filterController.dispose();
    _connection?.close();
    super.dispose();
  }

  bool get _hasPendingChanges =>
      _pendingUpdates.isNotEmpty ||
      _pendingInserts.isNotEmpty ||
      _pendingDeletes.isNotEmpty;

  TableKeyInfo? get _safeKey =>
      _tablePage?.safeKey ?? MySQLService.getPreferredSafeKey(_tableKeys);

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

    final matches = <String>[
      ..._sqlKeywords.where(
        (keyword) =>
            keyword.toLowerCase().startsWith(currentWord.toLowerCase()),
      ),
      ..._loadedTables.map((table) => table.name).where(
            (table) =>
                table.toLowerCase().startsWith(currentWord.toLowerCase()),
          ),
    ];

    setState(() {
      _suggestions = matches;
      _showAutocomplete = matches.isNotEmpty;
      _selectedSuggestionIndex = 0;
    });
  }

  List<TableSummary> get _loadedTables {
    if (_selectedDatabase != null &&
        _tablesByDatabase.containsKey(_selectedDatabase)) {
      return _tablesByDatabase[_selectedDatabase]!;
    }

    return _tablesByDatabase.values.expand((tables) => tables).toList();
  }

  void _insertSuggestion(String suggestion) {
    final text = _queryController.text;
    final cursorPos = _queryController.selection.baseOffset;

    if (cursorPos < 0) return;

    final textBeforeCursor = text.substring(0, cursorPos);
    final words = textBeforeCursor.split(RegExp(r'[\s,()]'));
    final currentWord = words.isNotEmpty ? words.last : '';

    final newCursorPos = cursorPos - currentWord.length + suggestion.length;
    final newText = text.substring(0, cursorPos - currentWord.length) +
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

    _queryFocusNode.requestFocus();
  }

  bool _handleQueryKeyEvent(KeyEvent event) {
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
    setState(() {
      _isConnecting = true;
      _connectionError = null;
      _isLoadingDatabases = true;
    });

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
        _isConnecting = false;
        _isLoadingDatabases = false;
      });

      final initialDatabase = widget.connection.database;
      if (initialDatabase != null && initialDatabase.isNotEmpty) {
        await _toggleDatabaseExpansion(initialDatabase, expandOnly: true);
      }
    } catch (e) {
      setState(() {
        _connectionError = 'Failed to connect: $e';
        _isConnecting = false;
        _isLoadingDatabases = false;
      });
    }
  }

  Future<void> _loadPersistedWorkspace() async {
    final history = await QueryWorkspaceStore.loadHistory(widget.connection.id);
    final snippets =
        await QueryWorkspaceStore.loadSnippets(widget.connection.id);

    if (!mounted) return;
    setState(() {
      _queryHistory = history;
      _querySnippets = snippets;
    });
  }

  Future<void> _toggleDatabaseExpansion(
    String database, {
    bool expandOnly = false,
  }) async {
    final isExpanded = _expandedDatabases.contains(database);

    if (isExpanded && !expandOnly) {
      setState(() {
        _expandedDatabases.remove(database);
        if (_selectedDatabase == database && _selection?.database != database) {
          _selectedDatabase = null;
        }
      });
      return;
    }

    setState(() {
      _selectedDatabase = database;
      _expandedDatabases.add(database);
    });

    if (_tablesByDatabase.containsKey(database) ||
        _loadingTableDatabases.contains(database)) {
      return;
    }

    if (_connection == null) return;

    setState(() {
      _tableError = null;
      _loadingTableDatabases.add(database);
    });

    try {
      await MySQLService.selectDatabase(_connection!, database);
      final tables =
          await MySQLService.getTableSummaries(_connection!, database);
      if (!mounted) return;

      setState(() {
        _tablesByDatabase[database] = tables;
        _loadingTableDatabases.remove(database);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tableError = 'Failed to load tables: $e';
        _loadingTableDatabases.remove(database);
      });
    }
  }

  Future<void> _selectTable(
    String database,
    TableSummary table, {
    bool openData = false,
  }) async {
    if (_connection == null) {
      return;
    }

    final selection = TableSelection(database: database, table: table.name);
    final isNewSelection = selection != _selection;

    if (isNewSelection) {
      final canContinue = await _guardTableNavigation(
        'Switch tables and discard pending table edits?',
      );
      if (!canContinue) {
        return;
      }
    }

    setState(() {
      if (isNewSelection) {
        _clearTableWorkspace();
        _pageRequest = const TablePageRequest();
        _filterController.clear();
      }
      _selection = selection;
      _selectedTableSummary = table;
      _selectedDatabase = database;
      _expandedDatabases.add(database);
      if (openData) {
        _workspaceMode = WorkspaceMode.data;
      }
    });

    await _loadTableMetadata();
    if (openData || _workspaceMode == WorkspaceMode.data) {
      await _loadTablePage();
    }
  }

  Future<void> _loadTableMetadata() async {
    if (_connection == null || _selection == null) return;

    setState(() {
      _isLoadingMetadata = true;
      _tableError = null;
    });

    try {
      final columns =
          await MySQLService.getTableColumns(_connection!, _selection!);
      final keys = await MySQLService.getTableKeys(_connection!, _selection!);

      if (!mounted) return;
      setState(() {
        _tableColumns = columns;
        _tableKeys = keys;
        _isLoadingMetadata = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tableError = 'Failed to load structure: $e';
        _isLoadingMetadata = false;
      });
    }
  }

  Future<void> _loadTablePage({bool guardPending = false}) async {
    if (_connection == null || _selection == null) return;
    if (guardPending) {
      final canContinue = await _guardTableNavigation(
        'Refresh table data and discard pending table edits?',
      );
      if (!canContinue) {
        return;
      }
    }
    if (_tableColumns.isEmpty) {
      await _loadTableMetadata();
    }

    setState(() {
      _isLoadingTablePage = true;
      _tableError = null;
    });

    try {
      final page = await MySQLService.fetchTablePage(
        _connection!,
        selection: _selection!,
        summary: _selectedTableSummary,
        keys: _tableKeys,
        request: _pageRequest,
      );

      if (!mounted) return;
      setState(() {
        _tablePage = page;
        _isLoadingTablePage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tableError = 'Failed to load data: $e';
        _isLoadingTablePage = false;
      });
    }
  }

  Future<void> _executeQuery() async {
    if (_connection == null || _queryController.text.trim().isEmpty) return;

    setState(() {
      _isExecuting = true;
      _queryError = null;
      _queryResult = null;
    });

    try {
      final result = await MySQLService.executeQuery(
        _connection!,
        _queryController.text,
      );

      await QueryWorkspaceStore.recordQuery(
        widget.connection.id,
        _queryController.text,
      );
      await _loadPersistedWorkspace();

      if (!mounted) return;
      setState(() {
        _queryResult = result;
        _isExecuting = false;
      });
    } catch (e) {
      await QueryWorkspaceStore.recordQuery(
        widget.connection.id,
        _queryController.text,
      );
      await _loadPersistedWorkspace();

      if (!mounted) return;
      setState(() {
        _queryError = 'Query error: $e';
        _isExecuting = false;
      });
    }
  }

  Future<void> _saveCurrentSnippet() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      return;
    }

    final nameController = TextEditingController(
      text: query.split('\n').first.trim().take(40),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          title: const Text('Save Snippet'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Snippet name',
              hintText: 'Recent user lookup',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (saved != true || nameController.text.trim().isEmpty) {
      return;
    }

    await QueryWorkspaceStore.saveSnippet(
      widget.connection.id,
      name: nameController.text,
      query: query,
    );
    await _loadPersistedWorkspace();
    if (!mounted) return;
    _showMessage('Snippet saved.');
  }

  Future<void> _deleteSnippet(QuerySnippet snippet) async {
    await QueryWorkspaceStore.deleteSnippet(widget.connection.id, snippet.id);
    await _loadPersistedWorkspace();
    if (!mounted) return;
    _showMessage('Snippet removed.');
  }

  Future<void> _changeWorkspaceMode(WorkspaceMode mode) async {
    setState(() {
      _workspaceMode = mode;
    });

    if (mode == WorkspaceMode.data && _selection != null) {
      await _loadTablePage();
    }

    if (mode == WorkspaceMode.structure && _selection != null) {
      await _loadTableMetadata();
    }
  }

  Future<bool> _guardTableNavigation(String message) async {
    if (!_hasPendingChanges) {
      return true;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          title: const Text('Discard staged changes?'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );

    if (discard == true) {
      setState(_discardPendingChanges);
      return true;
    }

    return false;
  }

  void _discardPendingChanges() {
    _pendingUpdates.clear();
    _pendingInserts.clear();
    _pendingDeletes.clear();
    _selectedRowIds.clear();
    _newRowCounter = 0;
  }

  void _clearTableWorkspace() {
    _selection = null;
    _selectedTableSummary = null;
    _tableColumns = [];
    _tableKeys = [];
    _tablePage = null;
    _discardPendingChanges();
  }

  void _openSelectionInQueryEditor() {
    if (_selection == null) return;

    _queryController.text =
        'SELECT * FROM `${_selection!.database}`.`${_selection!.table}` LIMIT 100;';
    _queryController.selection = TextSelection.collapsed(
      offset: _queryController.text.length,
    );
    _changeWorkspaceMode(WorkspaceMode.query);
  }

  void _applyFilter() {
    setState(() {
      _pageRequest = _pageRequest.copyWith(
        whereClause: _filterController.text.trim(),
        offset: 0,
      );
    });
    _loadTablePage(guardPending: true);
  }

  void _toggleSort(String columnName) {
    final isSameColumn = _pageRequest.sortColumn == columnName;
    setState(() {
      _pageRequest = _pageRequest.copyWith(
        sortColumn: columnName,
        descending: isSameColumn ? !_pageRequest.descending : false,
        offset: 0,
      );
    });
    _loadTablePage(guardPending: true);
  }

  void _changePage(int delta) {
    final nextOffset = _pageRequest.offset + delta;
    if (nextOffset < 0) {
      return;
    }

    setState(() {
      _pageRequest = _pageRequest.copyWith(offset: nextOffset);
    });
    _loadTablePage(guardPending: true);
  }

  void _addInsertRow() {
    if (_selection == null) return;

    final values = <String, String?>{
      for (final column in _tableColumns)
        if (!column.isAutoIncrement) column.name: column.defaultValue,
    };

    final rowId = 'new-${_newRowCounter++}';
    setState(() {
      _pendingInserts[rowId] = PendingRowChange(
        type: PendingRowChangeType.insert,
        rowId: rowId,
        values: values,
      );
    });
  }

  void _removeInsertRow(String rowId) {
    setState(() {
      _pendingInserts.remove(rowId);
    });
  }

  void _toggleRowSelection(String rowId, bool selected) {
    setState(() {
      if (selected) {
        _selectedRowIds.add(rowId);
      } else {
        _selectedRowIds.remove(rowId);
      }
    });
  }

  Future<void> _stageDeleteSelectedRows() async {
    if (_selectedRowIds.isEmpty || _tablePage == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          title: const Text('Mark rows for deletion?'),
          content: Text(
            'This will stage ${_selectedRowIds.length} row${_selectedRowIds.length == 1 ? '' : 's'} for deletion. The rows will not be removed until you apply changes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Mark for delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final selectedRows = _tablePage!.rows
        .where((row) => _selectedRowIds.contains(row.rowId))
        .toList();

    setState(() {
      for (final row in selectedRows) {
        _pendingDeletes.add(row.rowId);
        _pendingUpdates.remove(row.rowId);
      }
      _selectedRowIds.clear();
    });
  }

  void _undoDelete(String rowId) {
    setState(() {
      _pendingDeletes.remove(rowId);
    });
  }

  void _stageCellChange(
    _DisplayRow row,
    TableColumnInfo column,
    String input,
  ) {
    final normalized = _normalizeDraftValue(input, column);

    if (row.isInserted) {
      final current = _pendingInserts[row.rowId];
      if (current == null) return;

      final nextValues = Map<String, String?>.from(current.values);
      nextValues[column.name] = normalized;
      setState(() {
        _pendingInserts[row.rowId] = current.copyWith(values: nextValues);
      });
      return;
    }

    final originalValue = row.originalValues[column.name];
    final currentChange = _pendingUpdates[row.rowId];
    final nextValues = Map<String, String?>.from(currentChange?.values ?? {});

    if (normalized == originalValue) {
      nextValues.remove(column.name);
    } else {
      nextValues[column.name] = normalized;
    }

    setState(() {
      if (nextValues.isEmpty) {
        _pendingUpdates.remove(row.rowId);
      } else {
        _pendingUpdates[row.rowId] = PendingRowChange(
          type: PendingRowChangeType.update,
          rowId: row.rowId,
          keyValues: row.keyValues,
          values: nextValues,
        );
      }
    });
  }

  String? _normalizeDraftValue(String input, TableColumnInfo column) {
    if (input.isEmpty && column.isNullable) {
      return null;
    }
    return input;
  }

  Future<void> _applyChanges() async {
    if (_connection == null ||
        _selection == null ||
        _safeKey == null ||
        !_hasPendingChanges) {
      return;
    }

    final changeCount = _pendingInserts.length +
        _pendingUpdates.length +
        _pendingDeletes.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          title: const Text('Apply staged changes?'),
          content: Text(
            'This will apply $changeCount staged change${changeCount == 1 ? '' : 's'} to `${_selection!.table}`.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final changes = <PendingRowChange>[
      ..._pendingInserts.values,
      ..._pendingUpdates.values
          .where((change) => !_pendingDeletes.contains(change.rowId)),
      ..._pendingDeletes.map((rowId) {
        final record = _tablePage!.rows.firstWhere((row) => row.rowId == rowId);
        return PendingRowChange(
          type: PendingRowChangeType.delete,
          rowId: rowId,
          keyValues: record.keyValues,
        );
      }),
    ];

    setState(() {
      _isApplyingChanges = true;
      _tableError = null;
    });

    try {
      await MySQLService.applyTableChanges(
        _connection!,
        selection: _selection!,
        columns: _tableColumns,
        safeKey: _safeKey!,
        changes: changes,
      );

      if (!mounted) return;
      setState(() {
        _discardPendingChanges();
        _isApplyingChanges = false;
      });

      await _loadTablePage();
      _showMessage('Changes applied.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tableError = 'Failed to apply changes: $e';
        _isApplyingChanges = false;
      });
    }
  }

  Future<void> _exportCurrentPageCsv() async {
    if (_selection == null || _tablePage == null) {
      return;
    }

    final displayedRows =
        _buildDisplayRows().where((row) => !row.isDeleted).toList();
    final csv = _buildCsv(displayedRows);
    final directory = await _resolveExportDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File('${directory.path}/${_selection!.table}_$timestamp.csv');
    await file.writeAsString(csv);

    if (!mounted) return;
    _showMessage('Exported current page to ${file.path}');
  }

  Future<Directory> _resolveExportDirectory() async {
    final home = Platform.environment['HOME'];
    if (home != null) {
      final downloads = Directory('$home/Downloads');
      if (await downloads.exists()) {
        return downloads;
      }
    }

    return Directory.systemTemp;
  }

  String _buildCsv(List<_DisplayRow> rows) {
    final headers = _tableColumns.map((column) => column.name).toList();
    final lines = <String>[
      headers.map(_escapeCsvValue).join(','),
      ...rows.map((row) {
        final values = headers
            .map((header) => _escapeCsvValue(row.values[header] ?? ''))
            .join(',');
        return values;
      }),
    ];

    return lines.join('\n');
  }

  String _escapeCsvValue(String value) {
    final escaped = value.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n')) {
      return '"$escaped"';
    }
    return escaped;
  }

  void _loadQueryIntoEditor(String query) {
    _queryController.text = query;
    _queryController.selection = TextSelection.collapsed(
      offset: _queryController.text.length,
    );
    _changeWorkspaceMode(WorkspaceMode.query);
  }

  void _showRowDetails(_DisplayRow row) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          title: Text(
            row.isInserted
                ? 'New row draft'
                : 'Row details${row.isDeleted ? ' (marked for delete)' : ''}',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _tableColumns.map((column) {
                  final value = row.values[column.name];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          column.name,
                          style: const TextStyle(
                            color: AppTheme.mutedTextColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(value ?? 'NULL'),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isConnecting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_connectionError != null) {
      return Center(
        child: Text(
          _connectionError!,
          style: const TextStyle(
            color: AppTheme.errorColor,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Row(
      children: [
        _buildSidebar(),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              _buildWorkspaceHeader(),
              const SizedBox(height: 16),
              Expanded(
                child: switch (_workspaceMode) {
                  WorkspaceMode.query => _buildQueryWorkspace(),
                  WorkspaceMode.data => _buildDataWorkspace(),
                  WorkspaceMode.structure => _buildStructureWorkspace(),
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 300,
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
          Row(
            children: [
              const Icon(
                Icons.lan_rounded,
                size: 14,
                color: AppTheme.secondaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                '${widget.connection.host}:${widget.connection.port}',
                style: const TextStyle(
                  color: AppTheme.mutedTextColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Databases',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppTheme.mutedTextColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoadingDatabases
                ? const Center(child: CircularProgressIndicator())
                : _databases.isEmpty
                    ? const Center(
                        child: Text(
                          'No local databases available',
                          style: TextStyle(color: AppTheme.mutedTextColor),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _databases.length,
                        itemBuilder: (context, index) {
                          final database = _databases[index];
                          final tables =
                              _tablesByDatabase[database] ?? const [];
                          final isExpanded =
                              _expandedDatabases.contains(database);
                          final isLoading =
                              _loadingTableDatabases.contains(database);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _DatabaseItem(
                                name: database,
                                isSelected: _selectedDatabase == database,
                                isExpanded: isExpanded,
                                isLoading: isLoading,
                                onTap: () => _toggleDatabaseExpansion(database),
                              ),
                              if (isExpanded)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 18,
                                    top: 4,
                                    bottom: 10,
                                  ),
                                  child: isLoading
                                      ? const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : tables.isEmpty
                                          ? const Padding(
                                              padding:
                                                  EdgeInsets.only(bottom: 6),
                                              child: Text(
                                                'No tables',
                                                style: TextStyle(
                                                  color:
                                                      AppTheme.mutedTextColor,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            )
                                          : Column(
                                              children: tables.map((table) {
                                                final isSelected =
                                                    _selection?.database ==
                                                            database &&
                                                        _selection?.table ==
                                                            table.name;
                                                return _TableItem(
                                                  table: table,
                                                  isSelected: isSelected,
                                                  onTap: () => _selectTable(
                                                    database,
                                                    table,
                                                  ),
                                                  onDoubleTap: () =>
                                                      _selectTable(
                                                    database,
                                                    table,
                                                    openData: true,
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                ),
                            ],
                          );
                        },
                      ),
          ),
          if (_tableError != null) ...[
            const SizedBox(height: 12),
            Text(
              _tableError!,
              style: const TextStyle(
                color: AppTheme.errorColor,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkspaceHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: AppTheme.panelDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.connection.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _selection == null
                      ? 'Local MySQL workspace'
                      : 'Selected table: ${_selection!.qualifiedLabel}',
                  style: const TextStyle(
                    color: AppTheme.mutedTextColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (_selection != null) ...[
            TextButton.icon(
              onPressed: _openSelectionInQueryEditor,
              icon: const Icon(Icons.code_rounded, size: 18),
              label: const Text('Open in Query'),
            ),
            const SizedBox(width: 12),
          ],
          Wrap(
            spacing: 8,
            children: [
              _ModeButton(
                label: 'Query',
                icon: Icons.terminal_rounded,
                isSelected: _workspaceMode == WorkspaceMode.query,
                onTap: () => _changeWorkspaceMode(WorkspaceMode.query),
              ),
              _ModeButton(
                label: 'Data',
                icon: Icons.table_rows_rounded,
                isSelected: _workspaceMode == WorkspaceMode.data,
                onTap: () => _changeWorkspaceMode(WorkspaceMode.data),
              ),
              _ModeButton(
                label: 'Structure',
                icon: Icons.account_tree_rounded,
                isSelected: _workspaceMode == WorkspaceMode.structure,
                onTap: () => _changeWorkspaceMode(WorkspaceMode.structure),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueryWorkspace() {
    return Column(
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
                      const Text(
                        'SQL Editor',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Cmd + Enter to execute',
                        style: TextStyle(
                          color: AppTheme.mutedTextColor,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _saveCurrentSnippet,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Save Snippet'),
                      ),
                      const SizedBox(width: 12),
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
                        return _handleQueryKeyEvent(event)
                            ? KeyEventResult.handled
                            : KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _queryController,
                        focusNode: _queryFocusNode,
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
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: AppTheme.panelDecoration(),
                  child: _queryError != null
                      ? Center(
                          child: Text(
                            _queryError!,
                            style: const TextStyle(
                              color: AppTheme.errorColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : _queryResult == null
                          ? const Center(
                              child: Text(
                                'Execute a query to see results',
                                style:
                                    TextStyle(color: AppTheme.mutedTextColor),
                              ),
                            )
                          : _buildQueryResultsTable(),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(width: 320, child: _buildQueryToolsPanel()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQueryToolsPanel() {
    return Container(
      decoration: AppTheme.panelDecoration(),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelSectionTitle(
            title: 'Snippets',
            action: TextButton(
              onPressed: _saveCurrentSnippet,
              child: const Text('Save current'),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _querySnippets.isEmpty
                ? const Text(
                    'No snippets saved yet.',
                    style: TextStyle(color: AppTheme.mutedTextColor),
                  )
                : ListView(
                    children: _querySnippets.map((snippet) {
                      return _MiniListItem(
                        icon: Icons.bookmark_outline_rounded,
                        title: snippet.name,
                        subtitle: snippet.query,
                        onTap: () => _loadQueryIntoEditor(snippet.query),
                        trailing: IconButton(
                          onPressed: () => _deleteSnippet(snippet),
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: AppTheme.mutedTextColor,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.borderColor),
          const SizedBox(height: 16),
          const _PanelSectionTitle(title: 'Recent Queries'),
          const SizedBox(height: 12),
          Expanded(
            child: _queryHistory.isEmpty
                ? const Text(
                    'No executed queries yet.',
                    style: TextStyle(color: AppTheme.mutedTextColor),
                  )
                : ListView(
                    children: _queryHistory.map((item) {
                      return _MiniListItem(
                        icon: Icons.history_rounded,
                        title: _formatHistoryTime(item.executedAt),
                        subtitle: item.query,
                        onTap: () => _loadQueryIntoEditor(item.query),
                        trailing: IconButton(
                          onPressed: () {
                            _loadQueryIntoEditor(item.query);
                            _executeQuery();
                          },
                          icon: const Icon(
                            Icons.play_arrow_rounded,
                            size: 18,
                            color: AppTheme.mutedTextColor,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataWorkspace() {
    if (_selection == null) {
      return _EmptyWorkspaceState(
        icon: Icons.table_rows_rounded,
        title: 'Choose a table to browse data',
        description:
            'Single click a table to inspect it, or double click to open it directly in data mode.',
      );
    }

    final displayedRows = _buildDisplayRows();
    final canEdit = _tablePage?.canEdit ?? false;

    return Column(
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
                  Text(
                    _selection!.qualifiedLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(width: 12),
                  if (_selectedTableSummary != null)
                    _MetaPill(
                      icon: _selectedTableSummary!.isView
                          ? Icons.visibility_rounded
                          : Icons.table_chart_rounded,
                      label: _selectedTableSummary!.type,
                    ),
                  const SizedBox(width: 8),
                  if (_selectedTableSummary?.rowEstimate != null)
                    _MetaPill(
                      icon: Icons.format_list_numbered_rounded,
                      label: '~${_selectedTableSummary!.rowEstimate} rows',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_tablePage?.readOnlyReason != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF221C12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.secondaryColor),
                  ),
                  child: Text(
                    _tablePage!.readOnlyReason!,
                    style: const TextStyle(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (_tablePage?.readOnlyReason != null)
                const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _filterController,
                      onSubmitted: (_) => _applyFilter(),
                      decoration: const InputDecoration(
                        labelText: 'Filter (raw WHERE clause)',
                        hintText: 'status = "active" AND age > 18',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _applyFilter,
                    icon: const Icon(Icons.filter_alt_outlined, size: 18),
                    label: const Text('Apply'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _loadTablePage(guardPending: true),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _exportCurrentPageCsv,
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: const Text('Export CSV'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canEdit)
                    OutlinedButton.icon(
                      onPressed: _addInsertRow,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Insert Row'),
                    ),
                  if (canEdit)
                    OutlinedButton.icon(
                      onPressed: _selectedRowIds.isEmpty
                          ? null
                          : _stageDeleteSelectedRows,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete Selected'),
                    ),
                  if (_hasPendingChanges)
                    OutlinedButton.icon(
                      onPressed: () => setState(_discardPendingChanges),
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('Discard Changes'),
                    ),
                  if (_hasPendingChanges)
                    AppButton(
                      text: 'Apply Changes',
                      icon: Icons.save_rounded,
                      onPressed: _applyChanges,
                      isLoading: _isApplyingChanges,
                      color: AppTheme.secondaryColor,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: AppTheme.panelDecoration(),
            child: _isLoadingMetadata || _isLoadingTablePage
                ? const Center(child: CircularProgressIndicator())
                : _tableError != null
                    ? Center(
                        child: Text(
                          _tableError!,
                          style: const TextStyle(
                            color: AppTheme.errorColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : _tablePage == null
                        ? const Center(
                            child: Text(
                              'Choose a table to load data.',
                              style: TextStyle(color: AppTheme.mutedTextColor),
                            ),
                          )
                        : _buildDataGrid(displayedRows),
          ),
        ),
      ],
    );
  }

  Widget _buildDataGrid(List<_DisplayRow> rows) {
    final totalRows = _tablePage?.totalRows ?? 0;
    final pageStart = totalRows == 0 ? 0 : _pageRequest.offset + 1;
    final pageEnd =
        (_pageRequest.offset + _pageRequest.limit).clamp(0, totalRows);
    final hasPreviousPage = _pageRequest.offset > 0;
    final hasNextPage = _pageRequest.offset + _pageRequest.limit < totalRows;

    return Column(
      children: [
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: AppTheme.borderColor,
                  ),
                  child: DataTable(
                    columnSpacing: 24,
                    columns: [
                      const DataColumn(label: Text('State')),
                      ..._tableColumns.map((column) {
                        final isSorted = _pageRequest.sortColumn == column.name;
                        final sortIcon = isSorted
                            ? _pageRequest.descending
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded
                            : Icons.unfold_more_rounded;
                        return DataColumn(
                          label: InkWell(
                            onTap: () => _toggleSort(column.name),
                            child: Row(
                              children: [
                                Text(column.name),
                                const SizedBox(width: 6),
                                Icon(
                                  sortIcon,
                                  size: 14,
                                  color: AppTheme.mutedTextColor,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const DataColumn(label: Text('Actions')),
                    ],
                    rows: rows.map((row) {
                      return DataRow(
                        color: WidgetStatePropertyAll(
                          row.isDeleted
                              ? const Color(0xFF231516)
                              : row.isInserted
                                  ? const Color(0xFF142118)
                                  : null,
                        ),
                        cells: [
                          DataCell(_buildStateCell(row)),
                          ..._tableColumns.map((column) {
                            return DataCell(_buildTableCell(row, column));
                          }),
                          DataCell(_buildRowActions(row)),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Showing $pageStart-$pageEnd of $totalRows rows',
              style: const TextStyle(color: AppTheme.mutedTextColor),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: hasPreviousPage
                  ? () => _changePage(-_pageRequest.limit)
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
              label: const Text('Previous'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed:
                  hasNextPage ? () => _changePage(_pageRequest.limit) : null,
              icon: const Icon(Icons.chevron_right_rounded),
              label: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStateCell(_DisplayRow row) {
    if (row.isInserted) {
      return const _StateBadge(
        icon: Icons.add_circle_outline_rounded,
        label: 'New',
        color: AppTheme.successColor,
      );
    }

    if (row.isDeleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _StateBadge(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            color: AppTheme.errorColor,
          ),
          IconButton(
            onPressed: () => _undoDelete(row.rowId),
            icon: const Icon(
              Icons.undo_rounded,
              size: 18,
              color: AppTheme.mutedTextColor,
            ),
          ),
        ],
      );
    }

    if (_tablePage?.canEdit == true) {
      return Checkbox(
        value: _selectedRowIds.contains(row.rowId),
        onChanged: (selected) {
          _toggleRowSelection(row.rowId, selected ?? false);
        },
      );
    }

    return const _StateBadge(
      icon: Icons.lock_outline_rounded,
      label: 'Read only',
      color: AppTheme.mutedTextColor,
    );
  }

  Widget _buildTableCell(_DisplayRow row, TableColumnInfo column) {
    final value = row.values[column.name];
    final isEditable = (row.isInserted || (_tablePage?.canEdit ?? false)) &&
        !row.isDeleted &&
        !column.isAutoIncrement;

    if (!isEditable) {
      return SizedBox(
        width: 160,
        child: Text(
          value ?? 'NULL',
          style: TextStyle(
            color:
                value == null ? AppTheme.mutedTextColor : AppTheme.primaryColor,
            decoration: row.isDeleted ? TextDecoration.lineThrough : null,
          ),
        ),
      );
    }

    return SizedBox(
      width: 180,
      child: TextFormField(
        key: ValueKey('${row.rowId}:${column.name}'),
        initialValue: value ?? '',
        onChanged: (input) => _stageCellChange(row, column, input),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: column.isNullable ? 'NULL' : '',
        ),
        style: const TextStyle(
          color: AppTheme.primaryColor,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildRowActions(_DisplayRow row) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => _showRowDetails(row),
          icon: const Icon(
            Icons.open_in_full_rounded,
            size: 18,
            color: AppTheme.mutedTextColor,
          ),
        ),
        if (row.isInserted)
          IconButton(
            onPressed: () => _removeInsertRow(row.rowId),
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppTheme.mutedTextColor,
            ),
          ),
      ],
    );
  }

  Widget _buildStructureWorkspace() {
    if (_selection == null) {
      return _EmptyWorkspaceState(
        icon: Icons.account_tree_rounded,
        title: 'Choose a table to inspect structure',
        description:
            'Structure mode shows columns, defaults, indexes, and safe row identity information.',
      );
    }

    return Container(
      decoration: AppTheme.panelDecoration(),
      padding: const EdgeInsets.all(18),
      child: _isLoadingMetadata
          ? const Center(child: CircularProgressIndicator())
          : _tableError != null
              ? Center(
                  child: Text(
                    _tableError!,
                    style: const TextStyle(
                      color: AppTheme.errorColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : ListView(
                  children: [
                    Row(
                      children: [
                        Text(
                          _selection!.qualifiedLabel,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(width: 12),
                        if (_safeKey != null)
                          _MetaPill(
                            icon: Icons.verified_user_outlined,
                            label: 'Safe key: ${_safeKey!.displayLabel}',
                          )
                        else
                          const _MetaPill(
                            icon: Icons.lock_outline_rounded,
                            label: 'Read-only table',
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Columns',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Column')),
                          DataColumn(label: Text('Type')),
                          DataColumn(label: Text('Nullable')),
                          DataColumn(label: Text('Default')),
                          DataColumn(label: Text('Key')),
                          DataColumn(label: Text('Extra')),
                        ],
                        rows: _tableColumns.map((column) {
                          return DataRow(
                            cells: [
                              DataCell(Text(column.name)),
                              DataCell(Text(column.type)),
                              DataCell(Text(column.isNullable ? 'YES' : 'NO')),
                              DataCell(Text(column.defaultValue ?? 'NULL')),
                              DataCell(
                                  Text(column.key.isEmpty ? '-' : column.key)),
                              DataCell(Text(
                                  column.extra.isEmpty ? '-' : column.extra)),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Indexes',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 12),
                    if (_tableKeys.isEmpty)
                      const Text(
                        'No indexes detected.',
                        style: TextStyle(color: AppTheme.mutedTextColor),
                      )
                    else
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _tableKeys.map((key) {
                          return Container(
                            width: 240,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.elevatedSurfaceColor,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  key.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  key.displayLabel,
                                  style: const TextStyle(
                                    color: AppTheme.mutedTextColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  key.isPrimary
                                      ? 'Primary key'
                                      : key.isUnique
                                          ? 'Unique index'
                                          : 'Secondary index',
                                  style: const TextStyle(
                                    color: AppTheme.secondaryColor,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
    );
  }

  Widget _buildQueryResultsTable() {
    if (_queryResult == null) return const SizedBox();

    final columns = _queryResult!.cols.map((col) => col.name).toList();
    final rows = _queryResult!.rows;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: AppTheme.borderColor),
          child: DataTable(
            columns: columns
                .map((column) => DataColumn(label: Text(column)))
                .toList(),
            rows: rows.map((row) {
              return DataRow(
                cells: row.typedAssoc().values.map((value) {
                  return DataCell(
                    Text(
                      value?.toString() ?? 'NULL',
                      style: const TextStyle(color: AppTheme.mutedTextColor),
                    ),
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  List<_DisplayRow> _buildDisplayRows() {
    final rows = <_DisplayRow>[
      ..._pendingInserts.values.map((change) {
        return _DisplayRow(
          rowId: change.rowId,
          values: change.values,
          originalValues: const {},
          keyValues: const {},
          isInserted: true,
          isDeleted: false,
        );
      }),
    ];

    if (_tablePage == null) {
      return rows;
    }

    rows.addAll(
      _tablePage!.rows.map((record) {
        final update = _pendingUpdates[record.rowId];
        final values = Map<String, String?>.from(record.values);
        if (update != null) {
          values.addAll(update.values);
        }

        return _DisplayRow(
          rowId: record.rowId,
          values: values,
          originalValues: record.values,
          keyValues: record.keyValues,
          isInserted: false,
          isDeleted: _pendingDeletes.contains(record.rowId),
        );
      }),
    );

    return rows;
  }

  String _formatHistoryTime(DateTime timestamp) {
    final now = DateTime.now();
    final isToday = now.year == timestamp.year &&
        now.month == timestamp.month &&
        now.day == timestamp.day;

    final hh = timestamp.hour.toString().padLeft(2, '0');
    final mm = timestamp.minute.toString().padLeft(2, '0');
    if (isToday) {
      return 'Today $hh:$mm';
    }

    final month = timestamp.month.toString().padLeft(2, '0');
    final day = timestamp.day.toString().padLeft(2, '0');
    return '$month/$day $hh:$mm';
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppTheme.elevatedSurfaceColor : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  isSelected ? AppTheme.secondaryColor : AppTheme.borderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? AppTheme.primaryColor
                    : AppTheme.mutedTextColor,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.mutedTextColor,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelSectionTitle extends StatelessWidget {
  final String title;
  final Widget? action;

  const _PanelSectionTitle({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const Spacer(),
        if (action != null) action!,
      ],
    );
  }
}

class _MiniListItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const _MiniListItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.elevatedSurfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.mutedTextColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.mutedTextColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.elevatedSurfaceColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.secondaryColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.primaryColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyWorkspaceState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _EmptyWorkspaceState({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.panelDecoration(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: AppTheme.secondaryColor),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.mutedTextColor,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StateBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DatabaseItem extends StatelessWidget {
  final String name;
  final bool isSelected;
  final bool isExpanded;
  final bool isLoading;
  final VoidCallback onTap;

  const _DatabaseItem({
    required this.name,
    required this.isSelected,
    required this.isExpanded,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected ? const Color(0xFF1B232C) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: isSelected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderColor),
                  )
                : null,
            child: Row(
              children: [
                Icon(
                  Icons.storage_rounded,
                  color: isSelected
                      ? AppTheme.secondaryColor
                      : AppTheme.mutedTextColor,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.mutedTextColor,
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color: AppTheme.mutedTextColor,
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
  final TableSummary table;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _TableItem({
    required this.table,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? const Color(0xFF1B232C) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: isSelected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderColor),
                  )
                : null,
            child: Row(
              children: [
                Icon(
                  table.isView
                      ? Icons.visibility_rounded
                      : Icons.table_chart_rounded,
                  size: 15,
                  color: isSelected
                      ? AppTheme.secondaryColor
                      : AppTheme.mutedTextColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    table.name,
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.mutedTextColor,
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
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

class _DisplayRow {
  final String rowId;
  final Map<String, String?> values;
  final Map<String, String?> originalValues;
  final Map<String, String?> keyValues;
  final bool isInserted;
  final bool isDeleted;

  const _DisplayRow({
    required this.rowId,
    required this.values,
    required this.originalValues,
    required this.keyValues,
    required this.isInserted,
    required this.isDeleted,
  });
}

extension on String {
  String take(int length) {
    if (this.length <= length) {
      return this;
    }
    return substring(0, length);
  }
}
