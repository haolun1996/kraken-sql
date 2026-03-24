enum WorkspaceMode { query, data, structure }

enum PendingRowChangeType { insert, update, delete }

class TableSelection {
  final String database;
  final String table;

  const TableSelection({
    required this.database,
    required this.table,
  });

  String get qualifiedLabel => '$database.$table';

  @override
  bool operator ==(Object other) {
    return other is TableSelection &&
        other.database == database &&
        other.table == table;
  }

  @override
  int get hashCode => Object.hash(database, table);
}

class TableSummary {
  final String name;
  final String type;
  final int? rowEstimate;

  const TableSummary({
    required this.name,
    required this.type,
    this.rowEstimate,
  });

  bool get isView => type.toUpperCase().contains('VIEW');
}

class TableColumnInfo {
  final String name;
  final String type;
  final bool isNullable;
  final String? defaultValue;
  final String key;
  final String extra;
  final int position;

  const TableColumnInfo({
    required this.name,
    required this.type,
    required this.isNullable,
    required this.defaultValue,
    required this.key,
    required this.extra,
    required this.position,
  });

  bool get isPrimary => key.toUpperCase() == 'PRI';

  bool get isUnique => key.toUpperCase() == 'UNI' || isPrimary;

  bool get isAutoIncrement => extra.toLowerCase().contains('auto_increment');
}

class TableKeyInfo {
  final String name;
  final List<String> columns;
  final bool isPrimary;
  final bool isUnique;

  const TableKeyInfo({
    required this.name,
    required this.columns,
    required this.isPrimary,
    required this.isUnique,
  });

  String get displayLabel => columns.join(', ');
}

class TablePageRequest {
  final int limit;
  final int offset;
  final String whereClause;
  final String? sortColumn;
  final bool descending;

  const TablePageRequest({
    this.limit = 100,
    this.offset = 0,
    this.whereClause = '',
    this.sortColumn,
    this.descending = false,
  });

  TablePageRequest copyWith({
    int? limit,
    int? offset,
    String? whereClause,
    String? sortColumn,
    bool? descending,
    bool clearSort = false,
  }) {
    return TablePageRequest(
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      whereClause: whereClause ?? this.whereClause,
      sortColumn: clearSort ? null : (sortColumn ?? this.sortColumn),
      descending: descending ?? this.descending,
    );
  }
}

class TableRecord {
  final String rowId;
  final Map<String, String?> values;
  final Map<String, String?> keyValues;

  const TableRecord({
    required this.rowId,
    required this.values,
    required this.keyValues,
  });
}

class TablePageData {
  final List<TableRecord> rows;
  final int totalRows;
  final TableKeyInfo? safeKey;
  final bool canEdit;
  final String? readOnlyReason;

  const TablePageData({
    required this.rows,
    required this.totalRows,
    required this.safeKey,
    required this.canEdit,
    required this.readOnlyReason,
  });
}

class PendingRowChange {
  final PendingRowChangeType type;
  final String rowId;
  final Map<String, String?> keyValues;
  final Map<String, String?> values;

  const PendingRowChange({
    required this.type,
    required this.rowId,
    this.keyValues = const {},
    this.values = const {},
  });

  PendingRowChange copyWith({
    PendingRowChangeType? type,
    Map<String, String?>? keyValues,
    Map<String, String?>? values,
  }) {
    return PendingRowChange(
      type: type ?? this.type,
      rowId: rowId,
      keyValues: keyValues ?? this.keyValues,
      values: values ?? this.values,
    );
  }
}

class QueryHistoryItem {
  final String id;
  final String query;
  final DateTime executedAt;

  const QueryHistoryItem({
    required this.id,
    required this.query,
    required this.executedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'query': query,
      'executedAt': executedAt.toIso8601String(),
    };
  }

  factory QueryHistoryItem.fromJson(Map<String, dynamic> json) {
    return QueryHistoryItem(
      id: json['id'] as String,
      query: json['query'] as String,
      executedAt: DateTime.parse(json['executedAt'] as String),
    );
  }
}

class QuerySnippet {
  final String id;
  final String name;
  final String query;

  const QuerySnippet({
    required this.id,
    required this.name,
    required this.query,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'query': query,
    };
  }

  factory QuerySnippet.fromJson(Map<String, dynamic> json) {
    return QuerySnippet(
      id: json['id'] as String,
      name: json['name'] as String,
      query: json['query'] as String,
    );
  }
}
