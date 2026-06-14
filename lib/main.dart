import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'core/services/settings_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_fonts.dart';
import 'core/theme/theme_spec.dart';
import 'features/shell/app_shell.dart';
import 'features/updater/update_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Load settings before building UI so activeTabProvider can read startupTab.
  final container = ProviderContainer();
  await container.read(settingsProvider.notifier).load();

  // Preload all theme font families so switching never triggers an async
  // font-load + relayout.  Non-blocking — first paint isn't delayed.
  unawaited(preloadThemeFonts());

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1100, 740),
      minimumSize: Size(860, 600),
      center: true,
      title: 'mStorage',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const MStorageApp()),
  );

  // Background update check after first frame — single HTTP call, non-blocking.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(container.read(updateProvider.notifier).checkForUpdate());
  });
}

class MStorageApp extends ConsumerWidget {
  const MStorageApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-skin the whole app when the selected theme changes. Keeping the active
    // spec in sync here (idempotent) guarantees the getter-backed `k*` tokens
    // and `tabPalettes` resolve correctly before the subtree rebuilds.
    final themeId = ref.watch(settingsProvider.select((s) => s.themeId));
    applyThemeGlobals(appThemeIdFromString(themeId));

    return MaterialApp(
      title: 'mStorage',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // The ValueKey forces a clean remount on theme switch so every widget
      // re-reads the new tokens. Feature state survives (Riverpod providers and
      // the module-level media_kit player are not tied to the widget tree).
      home: KeyedSubtree(key: ValueKey(themeId), child: const AppShell()),
    );
  }
}
