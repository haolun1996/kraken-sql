import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlbench/features/connection/data/connection_model.dart';
import 'package:sqlbench/features/query_editor/data/table_models.dart';

class ConnectionNotifier extends StateNotifier<List<ConnectionModel>> {
  ConnectionNotifier() : super([]) {
    _loadConnections();
  }

  static const _storageKey = 'saved_connections';

  Future<void> _loadConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final List<dynamic> jsonList = json.decode(jsonString);
        state = jsonList.map((json) => ConnectionModel.fromJson(json)).toList();
      }
    } catch (_) {
      state = [];
    }
  }

  Future<void> _saveConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString =
          json.encode(state.map((conn) => conn.toJson()).toList());
      await prefs.setString(_storageKey, jsonString);
    } catch (_) {
      // Best-effort persistence is fine here.
    }
  }

  void addConnection(ConnectionModel connection) {
    state = [...state, connection];
    _saveConnections();
  }

  void removeConnection(String id) {
    state = state.where((conn) => conn.id != id).toList();
    _saveConnections();
  }

  void updateConnection(ConnectionModel connection) {
    state = [
      for (final conn in state)
        if (conn.id == connection.id) connection else conn,
    ];
    _saveConnections();
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, List<ConnectionModel>>((ref) {
  return ConnectionNotifier();
});

final activeConnectionProvider = StateProvider<ConnectionModel?>((ref) => null);

class MySQLService {
  static const allowedLocalHosts = {'localhost', '127.0.0.1', '::1'};

  static String? validateLocalHost(String host) {
    final normalized = host.trim().toLowerCase();
    if (allowedLocalHosts.contains(normalized)) {
      return null;
    }

    return 'SQLBench currently supports local MySQL only. Use localhost, 127.0.0.1, or ::1.';
  }

  static Future<MySQLConnection> connect(ConnectionModel model) async {
    final localHostError = validateLocalHost(model.host);
    if (localHostError != null) {
      throw Exception(localHostError);
    }

    try {
      final conn = await MySQLConnection.createConnection(
        host: model.host.trim(),
        port: model.port,
        userName: model.username,
        password: model.password,
        databaseName: model.database,
      );

      await conn.connect();
      return conn;
    } catch (e) {
      final errorMessage = e.toString();
      if (errorMessage.contains('Connection refused') ||
          errorMessage.contains('Failed host lookup')) {
        throw Exception(
          'Cannot connect to local MySQL at ${model.host}:${model.port}. Make sure MySQL is running.',
        );
      } else if (errorMessage.contains('Access denied')) {
        throw Exception(
          'Access denied for user ${model.username}. Check username and password.',
        );
      } else if (errorMessage.contains('Unknown database')) {
        throw Exception('Database "${model.database}" does not exist.');
      } else if (errorMessage.contains('timeout')) {
        throw Exception(
            'Connection timeout. Check if local MySQL is accessible.');
      } else {
        throw Exception('Connection failed: $errorMessage');
      }
    }
  }

  static Future<bool> testConnection(ConnectionModel model) async {
    try {
      final conn = await connect(model);
      await conn.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<String>> getDatabases(MySQLConnection conn) async {
    final result = await conn.execute('SHOW DATABASES');
    return result.rows.map((row) => row.colAt(0) as String).toList();
  }

  static Future<List<String>> getTables(
    MySQLConnection conn,
    String database,
  ) async {
    final result = await conn.execute('SHOW TABLES FROM `$database`');
    return result.rows.map((row) => row.colAt(0) as String).toList();
  }

  static Future<List<TableSummary>> getTableSummaries(
    MySQLConnection conn,
    String database,
  ) async {
    final result = await conn.execute(
      '''
      SELECT TABLE_NAME, TABLE_TYPE, TABLE_ROWS
      FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = :database
      ORDER BY TABLE_NAME
      ''',
      {'database': database},
    );

    return result.rows.map((row) {
      final estimate = row.colByName('TABLE_ROWS');
      return TableSummary(
        name: row.colByName('TABLE_NAME') ?? '',
        type: row.colByName('TABLE_TYPE') ?? 'BASE TABLE',
        rowEstimate: estimate == null ? null : int.tryParse(estimate),
      );
    }).toList();
  }

  static Future<List<TableColumnInfo>> getTableColumns(
    MySQLConnection conn,
    TableSelection selection,
  ) async {
    final result = await conn.execute(
      '''
      SELECT
        COLUMN_NAME,
        COLUMN_TYPE,
        IS_NULLABLE,
        COLUMN_DEFAULT,
        COLUMN_KEY,
        EXTRA,
        ORDINAL_POSITION
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = :database AND TABLE_NAME = :table
      ORDER BY ORDINAL_POSITION
      ''',
      {
        'database': selection.database,
        'table': selection.table,
      },
    );

    return result.rows.map((row) {
      return TableColumnInfo(
        name: row.colByName('COLUMN_NAME') ?? '',
        type: row.colByName('COLUMN_TYPE') ?? '',
        isNullable: (row.colByName('IS_NULLABLE') ?? 'YES') == 'YES',
        defaultValue: row.colByName('COLUMN_DEFAULT'),
        key: row.colByName('COLUMN_KEY') ?? '',
        extra: row.colByName('EXTRA') ?? '',
        position: int.tryParse(row.colByName('ORDINAL_POSITION') ?? '') ?? 0,
      );
    }).toList();
  }

  static Future<List<TableKeyInfo>> getTableKeys(
    MySQLConnection conn,
    TableSelection selection,
  ) async {
    final result = await conn.execute(
      '''
      SELECT INDEX_NAME, COLUMN_NAME, NON_UNIQUE, SEQ_IN_INDEX
      FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = :database AND TABLE_NAME = :table
      ORDER BY INDEX_NAME, SEQ_IN_INDEX
      ''',
      {
        'database': selection.database,
        'table': selection.table,
      },
    );

    final grouped = <String, List<String>>{};
    final uniqueFlags = <String, bool>{};

    for (final row in result.rows) {
      final indexName = row.colByName('INDEX_NAME') ?? '';
      final columnName = row.colByName('COLUMN_NAME') ?? '';
      final nonUnique = row.colByName('NON_UNIQUE') ?? '1';

      grouped.putIfAbsent(indexName, () => []).add(columnName);
      uniqueFlags[indexName] = nonUnique == '0';
    }

    return grouped.entries.map((entry) {
      final isPrimary = entry.key == 'PRIMARY';
      return TableKeyInfo(
        name: entry.key,
        columns: entry.value,
        isPrimary: isPrimary,
        isUnique: isPrimary || (uniqueFlags[entry.key] ?? false),
      );
    }).toList();
  }

  static TableKeyInfo? getPreferredSafeKey(List<TableKeyInfo> keys) {
    for (final key in keys) {
      if (key.isPrimary) {
        return key;
      }
    }

    for (final key in keys) {
      if (key.isUnique) {
        return key;
      }
    }

    return null;
  }

  static Future<void> selectDatabase(
    MySQLConnection conn,
    String database,
  ) async {
    await conn.execute('USE `$database`');
  }

  static Future<IResultSet> executeQuery(
    MySQLConnection conn,
    String query,
  ) async {
    return conn.execute(query);
  }

  static Future<TablePageData> fetchTablePage(
    MySQLConnection conn, {
    required TableSelection selection,
    required TableSummary? summary,
    required List<TableKeyInfo> keys,
    required TablePageRequest request,
  }) async {
    final safeKey = getPreferredSafeKey(keys);
    final whereSql = request.whereClause.trim().isEmpty
        ? ''
        : ' WHERE ${request.whereClause.trim()}';

    final orderSql = _buildOrderBySql(request, safeKey);
    final tableSql = _qualifiedTable(selection.database, selection.table);

    final totalResult = await conn.execute(
      'SELECT COUNT(*) AS total_count FROM $tableSql$whereSql',
    );
    final total = int.tryParse(
          totalResult.rows.first.colByName('total_count') ?? '',
        ) ??
        0;

    final result = await conn.execute(
      'SELECT * FROM $tableSql$whereSql$orderSql LIMIT ${request.limit} OFFSET ${request.offset}',
    );

    final rows = <TableRecord>[];
    var index = 0;
    for (final row in result.rows) {
      final values = row.assoc();
      final keyValues = safeKey == null
          ? <String, String?>{}
          : {
              for (final column in safeKey.columns) column: values[column],
            };
      rows.add(
        TableRecord(
          rowId: safeKey == null
              ? 'row-${request.offset + index}'
              : json.encode(keyValues),
          values: values,
          keyValues: keyValues,
        ),
      );
      index++;
    }

    final isView = summary?.isView ?? false;
    final canEdit = safeKey != null && !isView;

    return TablePageData(
      rows: rows,
      totalRows: total,
      safeKey: safeKey,
      canEdit: canEdit,
      readOnlyReason: canEdit
          ? null
          : isView
              ? 'Views are read-only in v1.'
              : 'Editing requires a primary key or unique key.',
    );
  }

  static Future<void> applyTableChanges(
    MySQLConnection conn, {
    required TableSelection selection,
    required List<TableColumnInfo> columns,
    required TableKeyInfo safeKey,
    required List<PendingRowChange> changes,
  }) async {
    final columnMap = {for (final column in columns) column.name: column};
    final tableSql = _qualifiedTable(selection.database, selection.table);

    await conn.transactional((txn) async {
      for (final change in changes.where(
        (change) => change.type == PendingRowChangeType.insert,
      )) {
        await _applyInsert(txn, tableSql, columnMap, change);
      }

      for (final change in changes.where(
        (change) => change.type == PendingRowChangeType.update,
      )) {
        await _applyUpdate(txn, tableSql, columnMap, safeKey, change);
      }

      for (final change in changes.where(
        (change) => change.type == PendingRowChangeType.delete,
      )) {
        await _applyDelete(txn, tableSql, safeKey, change);
      }
    });
  }

  static Future<void> _applyInsert(
    MySQLConnection conn,
    String tableSql,
    Map<String, TableColumnInfo> columnMap,
    PendingRowChange change,
  ) async {
    final columns = <String>[];
    final values = <dynamic>[];

    for (final entry in change.values.entries) {
      final column = columnMap[entry.key];
      if (column == null || column.isAutoIncrement) {
        continue;
      }

      final normalized = _normalizeOutgoingValue(entry.value, column);
      if (normalized == null && column.defaultValue != null) {
        continue;
      }
      if (normalized == null && column.isAutoIncrement) {
        continue;
      }

      columns.add(entry.key);
      values.add(normalized);
    }

    final columnSql =
        columns.isEmpty ? '' : '(${columns.map(_quoteIdentifier).join(', ')})';
    final placeholderSql = columns.isEmpty
        ? ''
        : 'VALUES (${List.filled(columns.length, '?').join(', ')})';
    final sql = columns.isEmpty
        ? 'INSERT INTO $tableSql () VALUES ()'
        : 'INSERT INTO $tableSql $columnSql $placeholderSql';

    if (columns.isEmpty) {
      await conn.execute(sql);
      return;
    }

    final stmt = await conn.prepare(sql);
    try {
      await stmt.execute(values);
    } finally {
      await stmt.deallocate();
    }
  }

  static Future<void> _applyUpdate(
    MySQLConnection conn,
    String tableSql,
    Map<String, TableColumnInfo> columnMap,
    TableKeyInfo safeKey,
    PendingRowChange change,
  ) async {
    if (change.values.isEmpty) {
      return;
    }

    final assignments = <String>[];
    final params = <dynamic>[];

    for (final entry in change.values.entries) {
      final column = columnMap[entry.key];
      if (column == null || column.isAutoIncrement) {
        continue;
      }

      assignments.add('${_quoteIdentifier(entry.key)} = ?');
      params.add(_normalizeOutgoingValue(entry.value, column));
    }

    if (assignments.isEmpty) {
      return;
    }

    final where = _buildWhereClause(safeKey.columns, change.keyValues);
    params.addAll(where.params);

    final sql =
        'UPDATE $tableSql SET ${assignments.join(', ')} WHERE ${where.sql} LIMIT 1';
    final stmt = await conn.prepare(sql);
    try {
      final result = await stmt.execute(params);
      if (result.affectedRows == BigInt.zero) {
        final exists =
            await _rowExists(conn, tableSql, safeKey, change.keyValues);
        if (!exists) {
          throw Exception(
            'A row changed or disappeared before it could be updated. Refresh the table and try again.',
          );
        }
      }
    } finally {
      await stmt.deallocate();
    }
  }

  static Future<void> _applyDelete(
    MySQLConnection conn,
    String tableSql,
    TableKeyInfo safeKey,
    PendingRowChange change,
  ) async {
    final where = _buildWhereClause(safeKey.columns, change.keyValues);
    final stmt = await conn.prepare(
      'DELETE FROM $tableSql WHERE ${where.sql} LIMIT 1',
    );

    try {
      final result = await stmt.execute(where.params);
      if (result.affectedRows == BigInt.zero) {
        throw Exception(
          'A row changed or disappeared before it could be deleted. Refresh the table and try again.',
        );
      }
    } finally {
      await stmt.deallocate();
    }
  }

  static Future<bool> _rowExists(
    MySQLConnection conn,
    String tableSql,
    TableKeyInfo safeKey,
    Map<String, String?> keyValues,
  ) async {
    final where = _buildWhereClause(safeKey.columns, keyValues);
    final stmt = await conn.prepare(
      'SELECT 1 FROM $tableSql WHERE ${where.sql} LIMIT 1',
    );

    try {
      final result = await stmt.execute(where.params);
      return result.rows.isNotEmpty;
    } finally {
      await stmt.deallocate();
    }
  }

  static String _buildOrderBySql(
    TablePageRequest request,
    TableKeyInfo? safeKey,
  ) {
    final requestedColumn = request.sortColumn;
    if (requestedColumn != null && requestedColumn.isNotEmpty) {
      return ' ORDER BY ${_quoteIdentifier(requestedColumn)} ${request.descending ? 'DESC' : 'ASC'}';
    }

    if (safeKey != null && safeKey.columns.isNotEmpty) {
      return ' ORDER BY ${_quoteIdentifier(safeKey.columns.first)} ASC';
    }

    return '';
  }

  static _WhereClause _buildWhereClause(
    List<String> keyColumns,
    Map<String, String?> keyValues,
  ) {
    final params = <dynamic>[];
    final parts = keyColumns.map((column) {
      final value = keyValues[column];
      if (value == null) {
        return '${_quoteIdentifier(column)} IS NULL';
      }
      params.add(value);
      return '${_quoteIdentifier(column)} = ?';
    }).join(' AND ');

    return _WhereClause(sql: parts, params: params);
  }

  static String? _normalizeOutgoingValue(
    String? value,
    TableColumnInfo column,
  ) {
    if (value == null) {
      return null;
    }

    if (value.isEmpty && column.isNullable) {
      return null;
    }

    return value;
  }

  static String _qualifiedTable(String database, String table) {
    return '${_quoteIdentifier(database)}.${_quoteIdentifier(table)}';
  }

  static String _quoteIdentifier(String identifier) {
    final escaped = identifier.replaceAll('`', '``');
    return '`$escaped`';
  }
}

class _WhereClause {
  final String sql;
  final List<dynamic> params;

  const _WhereClause({
    required this.sql,
    required this.params,
  });
}
