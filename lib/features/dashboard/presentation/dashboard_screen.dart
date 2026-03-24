import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlbench/core/theme/app_theme.dart';
import 'package:sqlbench/features/connection/data/connection_model.dart';
import 'package:sqlbench/features/connection/data/connection_provider.dart';
import 'package:sqlbench/features/connection/presentation/connection_dialog.dart';
import 'package:sqlbench/features/query_editor/presentation/query_editor_screen.dart';
import 'package:sqlbench/ui/widgets/glass_button.dart';

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
        _activeConnectionIndex = _openConnections.indexWhere(
          (c) => c.id == connection.id,
        );
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
      body: Container(
        decoration: AppTheme.appBackgroundDecoration,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_activeConnectionIndex == null)
                  Container(
                    width: 250,
                    height: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: AppTheme.panelDecoration(elevated: true),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SQLBench',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Minimal SQL workspace',
                          style: TextStyle(color: AppTheme.mutedTextColor),
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
                if (_activeConnectionIndex == null) const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      if (_openConnections.isNotEmpty)
                        SizedBox(
                          height: 56,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _TopTab(
                                icon: Icons.home_rounded,
                                label: 'Home',
                                isSelected: _activeConnectionIndex == null,
                                onTap: () =>
                                    setState(() => _activeConnectionIndex = null),
                              ),
                              const SizedBox(width: 8),
                              ...List.generate(_openConnections.length, (index) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _TopTab(
                                    icon: Icons.storage_rounded,
                                    label: _openConnections[index].name,
                                    isSelected: _activeConnectionIndex == index,
                                    onTap: () => setState(
                                      () => _activeConnectionIndex = index,
                                    ),
                                    onClose: () => _closeConnection(index),
                                  ),
                                );
                              }),
                            ],
                          ),
                        )
                      else
                        Container(
                          height: 72,
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: AppTheme.panelDecoration(elevated: true),
                          child: Row(
                            children: [
                              Text(
                                _selectedIndex == 0
                                    ? 'Dashboard'
                                    : 'Connections',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: AppTheme.panelDecoration(elevated: true),
                          child: content,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
          'Overview',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            _StatCard(
              icon: Icons.storage_rounded,
              title: 'Connections',
              value: connections.length.toString(),
              color: AppTheme.secondaryColor,
            ),
            const SizedBox(width: 16),
            _StatCard(
              icon: Icons.code_rounded,
              title: 'Open Sessions',
              value: _openConnections.length.toString(),
              color: AppTheme.primaryColor,
            ),
          ],
        ),
        const Spacer(),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: AppTheme.elevatedSurfaceColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: const Icon(
                    Icons.terminal_rounded,
                    size: 38,
                    color: AppTheme.secondaryColor,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Focused database work, minus the visual noise.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Create a connection and jump straight into queries with a quieter dark workspace.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.mutedTextColor,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                GlassButton(
                  text: 'New Connection',
                  icon: Icons.add_rounded,
                  onPressed: () async {
                    await ConnectionDialog.show(context, ref);
                  },
                  color: AppTheme.secondaryColor,
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
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
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            GlassButton(
              text: 'New',
              icon: Icons.add_rounded,
              onPressed: () async {
                await ConnectionDialog.show(context, ref);
              },
              color: AppTheme.secondaryColor,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child:
              connections.isEmpty
                  ? const Center(
                    child: Text(
                      'No connections yet',
                      style: TextStyle(color: AppTheme.mutedTextColor),
                    ),
                  )
                  : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 3.2,
                        ),
                    itemCount: connections.length,
                    itemBuilder: (context, index) {
                      final conn = connections[index];
                      final isActive = _openConnections.any(
                        (c) => c.id == conn.id,
                      );
                      return _ConnectionCard(
                        connection: conn,
                        isActive: isActive,
                        onConnect: () => _openConnection(conn),
                        onDelete: () {
                          ref
                              .read(connectionProvider.notifier)
                              .removeConnection(conn.id);
                          final openIndex = _openConnections.indexWhere(
                            (c) => c.id == conn.id,
                          );
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
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isSelected ? const Color(0xFF1C232B) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration:
                isSelected
                    ? BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.borderColor),
                    )
                    : null,
            child: Row(
              children: [
                Icon(
                  icon,
                  color:
                      isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.mutedTextColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color:
                        isSelected
                            ? AppTheme.primaryColor
                            : AppTheme.mutedTextColor,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
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

class _TopTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _TopTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppTheme.elevatedSurfaceColor : AppTheme.surfaceColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppTheme.secondaryColor : AppTheme.borderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color:
                    isSelected
                        ? AppTheme.primaryColor
                        : AppTheme.mutedTextColor,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color:
                      isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.mutedTextColor,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (onClose != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: AppTheme.mutedTextColor,
                  ),
                ),
              ],
            ],
          ),
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
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: AppTheme.panelDecoration(),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.elevatedSurfaceColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.mutedTextColor,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.panelDecoration(selected: isActive),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppTheme.elevatedSurfaceColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.storage_rounded,
              color:
                  isActive ? AppTheme.secondaryColor : AppTheme.mutedTextColor,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  connection.name,
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${connection.host}:${connection.port}',
                  style: const TextStyle(
                    color: AppTheme.mutedTextColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          GlassButton(
            text: isActive ? 'Open' : 'Connect',
            icon: isActive ? Icons.open_in_new_rounded : Icons.link_rounded,
            onPressed: onConnect,
            color:
                isActive
                    ? AppTheme.secondaryColor
                    : AppTheme.elevatedSurfaceColor,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.mutedTextColor),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
