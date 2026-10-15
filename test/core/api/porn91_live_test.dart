import 'dart:io';

import 'package:flule34/core/api/porn91_api.dart';
import 'package:flule34/core/api/porn91_parser.dart';
import 'package:flule34/core/models/porn91_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_session_harness.dart';

// Opt-in only。默认跳过，避免 CI 依赖外部站点可用性。
// 需要真实联网验证时：
//   HARU_TEST_PORN91=1 flutter test --no-pub test/core/api/porn91_live_test.dart
void main() {
  final enabled = Platform.environment['HARU_TEST_PORN91'] != null;

  test(
    'live: 分类浏览、详情解析与直链可播放性',
    () async {
      final harness = TestSessionHarness.create();
      addTearDown(harness.dispose);
      final api = Porn91Api(sessionStore: harness.sessionStore);

      // 1. 分类浏览（列表请求同时预热会话）
      final items = await api.loadCategoryVideos(Porn91Category.hot, 1);
      expect(items, isNotEmpty, reason: '热门分类应返回条目');
      for (final video in items) {
        expect(video.id, isNotEmpty);
        expect(video.title, isNotEmpty);
        expect(video.siteId, Porn91Parser.siteId);
      }

      // 2. 详情：必须解析出可播放的直链，且不是全站诱饵
      final details = await api.loadVideoDetails(items.first);
      expect(details.sources, isNotEmpty, reason: '详情页应解析出播放源');
      final url = details.sources.single.url;
      expect(url, startsWith('https://'));
      expect(url, isNot(contains('358999.mp4')));
      expect(details.video.title, isNotEmpty);

      // 3. 直链真的可下载：HEAD 应有非零长度且支持 Range
      final request = await HttpClient().headUrl(Uri.parse(url));
      request.headers.set('User-Agent', Porn91Api.browserUserAgent);
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(response.contentLength, greaterThan(1 << 20));
      expect(response.headers.value('accept-ranges'), 'bytes');

      // 4. 同一实例再次取详情，仍应拿到同一条视频（预热只发生一次）
      final again = await api.loadVideoDetails(items.first);
      expect(again.sources.single.url, isNot(contains('358999.mp4')));
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'live: 列表里展示的封面与标题就是点进去的那条视频',
    () async {
      final harness = TestSessionHarness.create();
      addTearDown(harness.dispose);
      final api = Porn91Api(sessionStore: harness.sessionStore);

      final items = await api.loadCategoryVideos(Porn91Category.hot, 1);
      expect(items, isNotEmpty, reason: '热门分类应返回条目');
      // 站点自述每页 24 条；多出来的就是被 CSS 隐藏的错位卡片。
      expect(items, hasLength(24));
      expect(
        items.map((video) => video.id).toSet(),
        hasLength(24),
        reason: '可见卡片之间不会互相重复',
      );

      // 逐条回到详情页核对：封面编号与标题都必须属于同一条视频。
      // 详情页的海报编号与主源编号站点保证一致，因此用主源里的媒体编号
      // （/mp43/<ID>.mp4）当作“这条到底是谁”的权威判据。
      final mediaIdPattern = RegExp(r'/(\d+)\.mp4(?:[?#]|$)');
      final mismatched = <String>[];
      for (final item in items) {
        final details = await api.loadVideoDetails(item);
        final detailMediaId = mediaIdPattern
            .firstMatch(details.sources.single.url)
            ?.group(1);
        final thumbnail = item.thumbnailUrl;
        if (detailMediaId != null &&
            thumbnail != null &&
            !thumbnail.contains(detailMediaId)) {
          mismatched.add('${item.id} 封面=$thumbnail 详情媒体=$detailMediaId');
        }
        if (item.title.isNotEmpty && details.video.title.isNotEmpty) {
          // 站点只在列表标题前带 `[原创]` 前缀、详情页标题不带，两者是同一条；
          // 详情页标题也可能被站点截断。去掉前缀后比较前 8 个字即可区分
          // “是不是同一条”。
          final listTitle = item.title.replaceFirst(RegExp(r'^\[原创\]\s*'), '');
          final head = listTitle.length <= 8
              ? listTitle
              : listTitle.substring(0, 8);
          if (!details.video.title.contains(head)) {
            mismatched.add(
              '${item.id} 列表标题=${item.title} 详情标题=${details.video.title}',
            );
          }
        }
      }
      expect(mismatched, isEmpty, reason: '列表与详情对不上的条目：$mismatched');
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'live: 搜索返回该站结果',
    () async {
      final harness = TestSessionHarness.create();
      addTearDown(harness.dispose);
      final api = Porn91Api(sessionStore: harness.sessionStore);

      final results = await api.searchVideos('学生', 1);

      expect(results, isNotEmpty, reason: 'search_id 搜索应有结果');
      for (final video in results) {
        expect(video.id, isNotEmpty);
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
