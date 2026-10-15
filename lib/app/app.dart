import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/domain/app_settings.dart';
import '../l10n/generated/app_localizations.dart';
import '../shared/video_preview_overlay.dart';
import '../shared/hanime_cloudflare_gate.dart';
import 'providers.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class Flule34App extends ConsumerWidget {
  const Flule34App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final settingsRepository = ref.watch(appSettingsRepositoryProvider);

    return ListenableBuilder(
      listenable: settingsRepository,
      builder: (context, _) {
        final preference = settingsRepository.settings.theme;
        final language = settingsRepository.settings.language;
        return MaterialApp.router(
          title: 'HaRu',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: switch (preference) {
            AppThemePreference.system => ThemeMode.system,
            AppThemePreference.light => ThemeMode.light,
            AppThemePreference.dark => ThemeMode.dark,
          },
          locale: language.languageCode == null
              ? null
              : Locale(language.languageCode!),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          // 这两个浮层挂在 MaterialApp.builder 上，而 builder 子树位于
          // Router/Navigator 之上——那里没有 Overlay。弹窗内部含 Tooltip
          // 之类需要 Overlay 的组件，缺 Overlay 时 debug 模式会直接抛错并
          // 用红屏替换整棵子树。Overlay.wrap 只补一个空 Overlay 供这些
          // 组件挂载，不改变现有布局与命中测试。
          builder: (context, child) => Overlay.wrap(
            child: HanimeCloudflareGate(
              child: VideoPreviewOverlay(
                navigationListenable: router.routerDelegate,
                bottomInsetBuilder: (context) {
                  final path =
                      router.routerDelegate.currentConfiguration.uri.path;
                  if (!_showsBottomNavigation(path)) {
                    return 0;
                  }
                  return NavigationBarTheme.of(context).height ?? 80;
                },
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
    );
  }
}

bool _showsBottomNavigation(String path) {
  return path == '/' ||
      path == '/hanime' ||
      path == '/library' ||
      path.startsWith('/library/') ||
      path == '/profile' ||
      path.startsWith('/profile/');
}
