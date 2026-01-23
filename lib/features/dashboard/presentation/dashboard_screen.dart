import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlbench/core/theme/app_theme.dart';
import 'package:sqlbench/features/connection/data/connection_model.dart';
import 'package:sqlbench/features/connection/data/connection_provider.dart';
import 'package:sqlbench/features/connection/presentation/connection_dialog.dart';
import 'package:sqlbench/features/query_editor/presentation/query_editor_screen.dart';
import 'package:sqlbench/ui/widgets/glass_button.dart';
import 'package:sqlbench/ui/widgets/glass_container.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selectedIndex = 0;
  final List<ConnectionModel> _openConnections = [];
  int? _activeConnectionIndex;

  void _openConnection(ConnectionModel connection) {
    if (!_openConnections.any((c) => c.id == connection.id)) {
      setState(() {
        _openConnections.add(connection);
        _activeConnectionIndex = _openConnections.length - 1;
      });
    } else {
      setState(() {
        _activeConnectionIndex = _openConnections.indexWhere((c) => c.id == connection.id);
      });
    }
  }

  void _closeConnection(int index) {
    setState(() {
      _openConnections.removeAt(index);
      if (_activeConnectionIndex != null) {
        if (_activeConnectionIndex == index) {
          _activeConnectionIndex = null;
        } else if (_activeConnectionIndex! > index) {
          _activeConnectionIndex = _activeConnectionIndex! - 1;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final connections = ref.watch(connectionProvider);

    Widget content;
    if (_activeConnectionIndex != null) {
      content = QueryEditorScreen(
        key: ValueKey(_openConnections[_activeConnectionIndex!].id),
        connection: _openConnections[_activeConnectionIndex!],
      );
    } else {
      switch (_selectedIndex) {
        case 0:
          content = _buildDashboardContent(connections);
          break;
        case 1:
          content = _buildConnectionsList(connections);
          break;
        default:
          content = const SizedBox();
      }
    }

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
          child: Row(
            children: [
              // Sidebar
              if (_activeConnectionIndex == null)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GlassContainer(
                    width: 250,
                    height: double.infinity,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SQLBench',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 40),
                        _SidebarItem(
                          icon: Icons.dashboard_rounded,
                          label: 'Dashboard',
                          isSelected: _selectedIndex == 0,
                          onTap: () => setState(() => _selectedIndex = 0),
                        ),
                        _SidebarItem(
                          icon: Icons.storage_rounded,
                          label: 'Connections',
                          isSelected: _selectedIndex == 1,
                          onTap: () => setState(() => _selectedIndex = 1),
                        ),
                      ],
                    ),
                  ),
                ),

              // Main Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16.0,
                    horizontal: 0,
                  ).copyWith(right: 16.0, left: _activeConnectionIndex != null ? 16.0 : 0),
                  child: Column(
                    children: [
                      // Top Bar / Tabs
                      if (_openConnections.isNotEmpty)
                        Container(
                          height: 50,
                          margin: const EdgeInsets.only(bottom: 16),
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              // Home Button
                              GestureDetector(
                                onTap: () => setState(() => _activeConnectionIndex = null),
                                child: GlassContainer(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  gradient: _activeConnectionIndex == null
                                      ? LinearGradient(
                                          colors: [
                                            AppTheme.primaryColor.withOpacity(0.5),
                                            AppTheme.primaryColor.withOpacity(0.5),
                                          ],
                                        )
                                      : const LinearGradient(
                                          colors: [Colors.transparent, Colors.transparent],
                                        ),
                                  child: Icon(
                                    Icons.home_rounded,
                                    color: _activeConnectionIndex == null
                                        ? Colors.white
                                        : Colors.white60,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Connection Tabs
                              ...List.generate(_openConnections.length, (index) {
                                final isSelected = _activeConnectionIndex == index;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: GestureDetector(
                                    onTap: () => setState(() => _activeConnectionIndex = index),
                                    child: GlassContainer(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      gradient: isSelected
                                          ? LinearGradient(
                                              colors: [
                                                AppTheme.primaryColor.withOpacity(0.5),
                                                AppTheme.primaryColor.withOpacity(0.5),
                                              ],
                                            )
                                          : const LinearGradient(
                                              colors: [Colors.transparent, Colors.transparent],
                                            ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.storage_rounded,
                                            size: 16,
                                            color: isSelected ? Colors.white : Colors.white60,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _openConnections[index].name,
                                            style: TextStyle(
                                              color: isSelected ? Colors.white : Colors.white60,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => _closeConnection(index),
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 14,
                                              color: isSelected ? Colors.white : Colors.white60,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        )
                      else
                        GlassContainer(
                          height: 80,
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Text(
                                _selectedIndex == 0 ? 'Dashboard' : 'Connections',
                                style: Theme.of(
                                  context,
                                ).textTheme.titleLarge?.copyWith(color: Colors.white),
                              ),
                              const Spacer(),
                            ],
                          ),
                        ),

                      if (_openConnections.isNotEmpty)
                        const SizedBox(height: 0)
                      else
                        const SizedBox(height: 16),

                      // Content Area
                      Expanded(
                        child: GlassContainer(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          child: content,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardContent(List<ConnectionModel> connections) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Stats',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            _StatCard(
              icon: Icons.storage_rounded,
              title: 'Connections',
              value: connections.length.toString(),
              color: AppTheme.primaryColor,
            ),
            const SizedBox(width: 16),
            _StatCard(
              icon: Icons.code_rounded,
              title: 'Open',
              value: _openConnections.length.toString(),
              color: AppTheme.secondaryColor,
            ),
          ],
        ),
        const SizedBox(height: 40),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.rocket_launch_rounded,
                size: 64,
                color: AppTheme.secondaryColor.withOpacity(0.8),
              ),
              const SizedBox(height: 20),
              Text(
                'Welcome to SQLBench',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(color: Colors.white.withOpacity(0.9)),
              ),
              const SizedBox(height: 10),
              Text(
                'Create a connection to get started',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.white.withOpacity(0.6)),
              ),
              const SizedBox(height: 24),
              GlassButton(
                text: 'New Connection',
                icon: Icons.add,
                onPressed: () async {
                  await ConnectionDialog.show(context, ref);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionsList(List<ConnectionModel> connections) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Saved Connections',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            GlassButton(
              text: 'New',
              icon: Icons.add,
              onPressed: () async {
                await ConnectionDialog.show(context, ref);
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: connections.isEmpty
              ? Center(
                  child: Text(
                    'No connections yet',
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                )
              : ListView.builder(
                  itemCount: connections.length,
                  itemBuilder: (context, index) {
                    final conn = connections[index];
                    final isActive = _openConnections.any((c) => c.id == conn.id);
                    return _ConnectionCard(
                      connection: conn,
                      isActive: isActive,
                      onConnect: () => _openConnection(conn),
                      onDelete: () {
                        ref.read(connectionProvider.notifier).removeConnection(conn.id);
                        final openIndex = _openConnections.indexWhere((c) => c.id == conn.id);
                        if (openIndex != -1) {
                          _closeConnection(openIndex);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: isSelected
            ? BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.5)),
              )
            : null,
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.white.withOpacity(0.6), size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.6),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(20),
        gradient: LinearGradient(colors: [color.withOpacity(0.2), color.withOpacity(0.05)]),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final ConnectionModel connection;
  final bool isActive;
  final VoidCallback onConnect;
  final VoidCallback onDelete;

  const _ConnectionCard({
    required this.connection,
    required this.isActive,
    required this.onConnect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      gradient: isActive
          ? LinearGradient(
              colors: [
                AppTheme.primaryColor.withOpacity(0.3),
                AppTheme.primaryColor.withOpacity(0.1),
              ],
            )
          : null,
      child: Row(
        children: [
          Icon(Icons.storage_rounded, color: isActive ? AppTheme.secondaryColor : Colors.white70),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connection.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${connection.host}:${connection.port}',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                ),
              ],
            ),
          ),
          if (!isActive)
            GlassButton(text: 'Connect', icon: Icons.link, onPressed: onConnect)
          else
            GlassButton(text: 'Open', icon: Icons.open_in_new, onPressed: onConnect),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white54),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
