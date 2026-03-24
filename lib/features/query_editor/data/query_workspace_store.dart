import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlbench/features/query_editor/data/table_models.dart';

class QueryWorkspaceStore {
  static String _historyKey(String connectionId) =>
      'query_history_$connectionId';
  static String _snippetKey(String connectionId) =>
      'query_snippets_$connectionId';

  static Future<List<QueryHistoryItem>> loadHistory(String connectionId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey(connectionId));
    if (raw == null || raw.isEmpty) {
      return [];
    }

    final decoded = json.decode(raw) as List<dynamic>;
    return decoded
        .map((item) => QueryHistoryItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<void> recordQuery(String connectionId, String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final current = await loadHistory(connectionId);
    final deduped =
        current.where((item) => item.query.trim() != trimmed).toList();
    deduped.insert(
      0,
      QueryHistoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        query: trimmed,
        executedAt: DateTime.now(),
      ),
    );

    final limited = deduped.take(30).map((item) => item.toJson()).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey(connectionId), json.encode(limited));
  }

  static Future<List<QuerySnippet>> loadSnippets(String connectionId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snippetKey(connectionId));
    if (raw == null || raw.isEmpty) {
      return [];
    }

    final decoded = json.decode(raw) as List<dynamic>;
    return decoded
        .map((item) => QuerySnippet.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveSnippet(
    String connectionId, {
    required String name,
    required String query,
  }) async {
    final snippets = await loadSnippets(connectionId);
    snippets.insert(
      0,
      QuerySnippet(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name.trim(),
        query: query.trim(),
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _snippetKey(connectionId),
      json.encode(snippets.map((item) => item.toJson()).toList()),
    );
  }

  static Future<void> deleteSnippet(
    String connectionId,
    String snippetId,
  ) async {
    final snippets = await loadSnippets(connectionId);
    final updated = snippets.where((item) => item.id != snippetId).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _snippetKey(connectionId),
      json.encode(updated.map((item) => item.toJson()).toList()),
    );
  }
}
