class ConnectionModel {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;
  final String? database;

  ConnectionModel({
    required this.id,
    required this.name,
    required this.host,
    required this.username,
    required this.password,
    this.port = 3306,
    this.database,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'database': database,
    };
  }

  factory ConnectionModel.fromJson(Map<String, dynamic> json) {
    return ConnectionModel(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int? ?? 3306,
      username: json['username'] as String,
      password: json['password'] as String,
      database: json['database'] as String?,
    );
  }

  ConnectionModel copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    String? database,
  }) {
    return ConnectionModel(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      database: database ?? this.database,
    );
  }
}
