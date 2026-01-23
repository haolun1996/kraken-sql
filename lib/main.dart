import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlbench/core/theme/app_theme.dart';
import 'package:sqlbench/features/dashboard/presentation/dashboard_screen.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1200, 800),
    minimumSize: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: SqlBenchApp()));
}

class SqlBenchApp extends StatelessWidget {
  const SqlBenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SQLBench',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const KeyboardShortcutHandler(child: DashboardScreen()),
    );
  }
}

class KeyboardShortcutHandler extends StatelessWidget {
  final Widget child;

  const KeyboardShortcutHandler({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Cmd + W to close window
          if (event.logicalKey == LogicalKeyboardKey.keyW &&
              (event.physicalKey == PhysicalKeyboardKey.metaLeft ||
                  event.physicalKey == PhysicalKeyboardKey.metaRight ||
                  HardwareKeyboard.instance.isMetaPressed)) {
            windowManager.close();
            return KeyEventResult.handled;
          }
          // Cmd + M to minimize window
          if (event.logicalKey == LogicalKeyboardKey.keyM &&
              (event.physicalKey == PhysicalKeyboardKey.metaLeft ||
                  event.physicalKey == PhysicalKeyboardKey.metaRight ||
                  HardwareKeyboard.instance.isMetaPressed)) {
            windowManager.minimize();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
