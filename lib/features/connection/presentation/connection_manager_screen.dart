import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlbench/core/theme/app_theme.dart';
import 'package:sqlbench/features/connection/data/connection_model.dart';
import 'package:sqlbench/features/connection/data/connection_provider.dart';
import 'package:sqlbench/ui/widgets/glass_button.dart';
import 'package:sqlbench/ui/widgets/glass_text_field.dart';

class ConnectionManagerScreen extends ConsumerStatefulWidget {
  const ConnectionManagerScreen({super.key});

  @override
  ConsumerState<ConnectionManagerScreen> createState() =>
      _ConnectionManagerScreenState();
}

class _ConnectionManagerScreenState
    extends ConsumerState<ConnectionManagerScreen> {
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '3306');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _databaseController = TextEditingController();
  bool _isTesting = false;
  String? _testResult;

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _databaseController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final model = ConnectionModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      host: _hostController.text,
      port: int.tryParse(_portController.text) ?? 3306,
      username: _usernameController.text,
      password: _passwordController.text,
      database: _databaseController.text.isEmpty
          ? null
          : _databaseController.text,
    );

    try {
      final conn = await MySQLService.connect(model);
      await conn.close();
      setState(() {
        _isTesting = false;
        _testResult = '✓ Connection successful!';
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testResult = '✗ ${e.toString().replaceAll('Exception: ', '')}';
      });
    }
  }

  void _saveConnection() {
    final model = ConnectionModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      host: _hostController.text,
      port: int.tryParse(_portController.text) ?? 3306,
      username: _usernameController.text,
      password: _passwordController.text,
      database: _databaseController.text.isEmpty
          ? null
          : _databaseController.text,
    );

    ref.read(connectionProvider.notifier).addConnection(model);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2E0249), Color(0xFF000000), Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withOpacity(0.1),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'New Connection',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    GlassTextField(
                      label: 'Connection Name',
                      hint: 'Production DB',
                      controller: _nameController,
                    ),
                    const SizedBox(height: 20),
                    GlassTextField(
                      label: 'Host',
                      hint: 'localhost',
                      controller: _hostController,
                    ),
                    const SizedBox(height: 20),
                    GlassTextField(
                      label: 'Port',
                      hint: '3306',
                      controller: _portController,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 20),
                    GlassTextField(
                      label: 'Username',
                      hint: 'root',
                      controller: _usernameController,
                    ),
                    const SizedBox(height: 20),
                    GlassTextField(
                      label: 'Password',
                      hint: '••••••••',
                      controller: _passwordController,
                      obscureText: true,
                    ),
                    const SizedBox(height: 20),
                    GlassTextField(
                      label: 'Database (Optional)',
                      hint: 'my_database',
                      controller: _databaseController,
                    ),
                    const SizedBox(height: 24),
                    if (_testResult != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            color: _testResult!.contains('✓')
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        GlassButton(
                          text: 'Test Connection',
                          icon: Icons.check_circle_outline,
                          onPressed: _testConnection,
                          isLoading: _isTesting,
                          color: AppTheme.secondaryColor,
                        ),
                        const SizedBox(width: 12),
                        GlassButton(
                          text: 'Save',
                          icon: Icons.save,
                          onPressed: _saveConnection,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
