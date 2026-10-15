import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:flule34/app/app.dart';
import 'package:flule34/app/providers.dart';
import 'package:flule34/core/api/hanime1_api.dart';
import 'package:flule34/core/api/rule34video_api.dart';
import 'package:flule34/core/models/video_models.dart';
import 'package:flule34/core/session/session_store.dart';
import 'package:flule34/features/settings/data/app_settings_store.dart';

import 'helpers/test_session_harness.dart';

/// app 级浮层需要 [Overlay] 才能挂载其中的 Tooltip。
///
/// [HanimeCloudflareGate] 与 [VideoPreviewOverlay] 挂在 `MaterialApp.builder`
/// 上，而 builder 子树位于 Router/Navigator **之上**，那里没有 Overlay 祖先。
/// 验证弹窗里的 `IconButton(tooltip: …)` 因此会在 debug 模式下抛
/// 「No Overlay widget found」并用红屏替换整棵子树（实机 2.5.0 复现）。
/// `Overlay.wrap` 补上这个 Overlay，本测试锁定该回归。
void main() {
  testWidgets('Cloudflare 验证弹窗在 app 级浮层里能找到 Overlay 并渲染 Tooltip', (
    tester,
  ) async {
    // 本文件独立进程运行，测试结束后无需还原（setter 不接受 null）。
    WebViewPlatform.instance = _FakeWebViewPlatform();

    final harness = TestSessionHarness.create();
    addTearDown(harness.dispose);
    final api = _FakeApi(harness.sessionStore);
    final container = ProviderContainer(
      overrides: [
        rule34VideoApiProvider.overrideWithValue(api),
        appDatabaseProvider.overrideWithValue(harness.database),
        appSettingsStoreProvider.overrideWithValue(_MemorySettingsStore()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const Flule34App(),
      ),
    );
    await tester.pump();

    // 让 gate 弹出一张需要浏览器验证的卡片。
    final coordinator = container.read(hanimeCloudflareCoordinatorProvider);
    unawaited(coordinator.requestPage(Uri.parse('https://hanime1.me/')));
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      tester.takeException(),
      isNull,
      reason: '弹窗内的 Tooltip 缺 Overlay 会抛错',
    );
    // 弹窗背后的路由仍需正常渲染（补的 Overlay 不能遮住内容）。
    expect(find.byType(NavigationBar), findsOneWidget);

    // 长按弹窗里的关闭按钮：Tooltip 要真的能挂到 Overlay 上显示出来。
    // 用 IconButton 定位而不是文案，避免依赖当前 locale。
    final closeButton = find.widgetWithIcon(IconButton, Icons.close);
    expect(closeButton, findsOneWidget);
    await tester.longPress(closeButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Tooltip 已插入 Overlay，说明它成功找到了 Overlay 祖先。
    expect(find.byType(Tooltip), findsWidgets);

    coordinator.complete(requestId: 1);
    await tester.pumpAndSettle();
  });
}

class _FakeApi extends Rule34VideoApi {
  _FakeApi(SessionStore sessionStore)
    : super(
        sessionStore: sessionStore,
        hanimeApi: Hanime1Api(
          sessionStore: sessionStore,
          httpClientAdapter: _EmptyAdapter(),
        ),
      );

  @override
  Future<List<VideoItem>> loadFeed(
    FeedKind kind,
    int page, {
    SearchFilters filters = const SearchFilters(),
    bool force = false,
  }) async => const [];

  @override
  void close() {}
}

final class _EmptyAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '<html><body></body></html>',
      200,
      headers: {
        Headers.contentTypeHeader: ['text/html; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _MemorySettingsStore implements AppSettingsStore {
  final Map<String, Object> _values = {};

  @override
  Future<bool?> readBool(String key) async => _values[key] as bool?;

  @override
  Future<String?> readString(String key) async => _values[key] as String?;

  @override
  Future<void> writeBool(String key, bool value) async {
    _values[key] = value;
  }

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}

// --- 最小 WebView 平台替身：验证弹窗需要一个可用的 WebView 实现 ---------------

final class _FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _FakeWebViewController();

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _FakeNavigationDelegate();

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWebViewWidget(params);
}

final class _FakeWebViewController extends PlatformWebViewController {
  _FakeWebViewController()
    : super.implementation(const PlatformWebViewControllerCreationParams());

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<String?> currentUrl() async => 'https://hanime1.me/';

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async => '{}';

  @override
  Future<void> reload() async {}
}

final class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate()
    : super.implementation(const PlatformNavigationDelegateCreationParams());

  @override
  Future<void> setOnNavigationRequest(
    FutureOr<NavigationDecision> Function(NavigationRequest request)
    onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnPageStarted(
    void Function(String url) onPageStarted,
  ) async {}

  @override
  Future<void> setOnPageFinished(
    void Function(String url) onPageFinished,
  ) async {}

  @override
  Future<void> setOnProgress(void Function(int progress) onProgress) async {}

  @override
  Future<void> setOnWebResourceError(
    void Function(WebResourceError error) onWebResourceError,
  ) async {}
}

final class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
