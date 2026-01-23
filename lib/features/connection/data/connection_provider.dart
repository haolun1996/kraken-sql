import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlbench/features/connection/data/connection_model.dart';

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
    } catch (e) {
      // If loading fails, start with empty list
      state = [];
    }
  }

  Future<void> _saveConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(state.map((conn) => conn.toJson()).toList());
      await prefs.setString(_storageKey, jsonString);
    } catch (e) {
      // Silently fail if save fails
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

final connectionProvider = StateNotifierProvider<ConnectionNotifier, List<ConnectionModel>>((ref) {
  return ConnectionNotifier();
});

final activeConnectionProvider = StateProvider<ConnectionModel?>((ref) => null);

class MySQLService {
  static Future<MySQLConnection> connect(ConnectionModel model) async {
    try {
      final conn = await MySQLConnection.createConnection(
        host: model.host,
        port: model.port,
        userName: model.username,
        password: model.password,
        databaseName: model.database,
      );

      await conn.connect();
      return conn;
    } catch (e) {
      // Provide more detailed error messages
      String errorMessage = e.toString();
      if (errorMessage.contains('Connection refused') ||
          errorMessage.contains('Failed host lookup')) {
        throw Exception(
          'Cannot connect to MySQL server at ${model.host}:${model.port}. Make sure MySQL is running.',
        );
      } else if (errorMessage.contains('Access denied')) {
        throw Exception('Access denied for user ${model.username}. Check username and password.');
      } else if (errorMessage.contains('Unknown database')) {
        throw Exception('Database "${model.database}" does not exist.');
      } else if (errorMessage.contains('timeout')) {
        throw Exception('Connection timeout. Check if MySQL server is accessible.');
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
    } catch (e) {
      return false;
    }
  }

  static Future<List<String>> getDatabases(MySQLConnection conn) async {
    final result = await conn.execute('SHOW DATABASES');
    return result.rows.map((row) => row.colAt(0) as String).toList();
  }

  static Future<List<String>> getTables(MySQLConnection conn, String database) async {
    final result = await conn.execute('SHOW TABLES FROM `$database`');
    return result.rows.map((row) => row.colAt(0) as String).toList();
  }

  static Future<void> selectDatabase(MySQLConnection conn, String database) async {
    await conn.execute('USE `$database`');
  }

  static Future<IResultSet> executeQuery(MySQLConnection conn, String query) async {
    return await conn.execute(query);
  }
}
