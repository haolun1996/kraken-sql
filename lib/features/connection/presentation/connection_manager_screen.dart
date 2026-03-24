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
        _testResult = 'Connection successful';
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testResult = e.toString().replaceAll('Exception: ', '');
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
    final hasSuccess = _testResult == 'Connection successful';

    return Scaffold(
      body: Container(
        decoration: AppTheme.appBackgroundDecoration,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: AppTheme.panelDecoration(elevated: true),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: AppTheme.mutedTextColor,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'New Connection',
                              style: Theme.of(
                                context,
                              ).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Create a clean connection profile.',
                              style: TextStyle(color: AppTheme.mutedTextColor),
                            ),
                          ],
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
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: GlassTextField(
                            label: 'Host',
                            hint: 'localhost',
                            controller: _hostController,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GlassTextField(
                            label: 'Port',
                            hint: '3306',
                            controller: _portController,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: GlassTextField(
                            label: 'Username',
                            hint: 'root',
                            controller: _usernameController,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GlassTextField(
                            label: 'Password',
                            hint: '••••••••',
                            controller: _passwordController,
                            obscureText: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    GlassTextField(
                      label: 'Database (Optional)',
                      hint: 'my_database',
                      controller: _databaseController,
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color:
                              hasSuccess
                                  ? const Color(0xFF112219)
                                  : const Color(0xFF241414),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color:
                                hasSuccess
                                    ? AppTheme.successColor
                                    : AppTheme.errorColor,
                          ),
                        ),
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            color:
                                hasSuccess
                                    ? AppTheme.successColor
                                    : AppTheme.errorColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        GlassButton(
                          text: 'Test Connection',
                          icon: Icons.check_circle_outline,
                          onPressed: _testConnection,
                          isLoading: _isTesting,
                          color: AppTheme.elevatedSurfaceColor,
                        ),
                        const SizedBox(width: 12),
                        GlassButton(
                          text: 'Save',
                          icon: Icons.save_rounded,
                          onPressed: _saveConnection,
                          color: AppTheme.secondaryColor,
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
