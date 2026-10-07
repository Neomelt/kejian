import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'domain/models.dart' as model;
import 'ui/app_theme.dart';
import 'ui/import_page.dart';
import 'ui/schedule_page.dart';
import 'ui/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = ScheduleController();
  await controller.init();
  runApp(KejianApp(controller: controller));
}

class KejianApp extends StatelessWidget {
  const KejianApp({super.key, required this.controller});
  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final mode = controller.data.settings.darkMode;
        return MaterialApp(
          title: '课间',
          debugShowCheckedModeBanner: false,
          themeMode: mode == model.ThemeMode.light
              ? ThemeMode.light
              : mode == model.ThemeMode.dark
                  ? ThemeMode.dark
                  : ThemeMode.system,
          theme: buildKejianTheme(Brightness.light),
          darkTheme: buildKejianTheme(Brightness.dark),
          home: ScheduleShell(controller: controller),
        );
      },
    );
  }
}

class ScheduleShell extends StatefulWidget {
  const ScheduleShell({super.key, required this.controller});
  final ScheduleController controller;

  @override
  State<ScheduleShell> createState() => _ScheduleShellState();
}

class _ScheduleShellState extends State<ScheduleShell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      SchedulePage(controller: widget.controller),
      ImportPage(controller: widget.controller),
      SettingsPage(controller: widget.controller),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '课表',
          ),
          NavigationDestination(
            icon: Icon(Icons.file_upload_outlined),
            selectedIcon: Icon(Icons.file_upload),
            label: '导入',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
