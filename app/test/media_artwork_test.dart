import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/appearance.dart';
import 'package:uni_launcher/theme/launcher_theme.dart';
import 'package:uni_launcher/widgets/media_artwork.dart';

/// 1×1 透明 PNG：原生送来的 `artwork` 就是这个形状的 base64。
const pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==';

const fallbackAsset = 'assets/art/cover-default.png';

void main() {
  Widget host(Widget child) => MaterialApp(
      theme: launcherTheme(SurfaceStyle.from(const Appearance(), true)),
      home: Scaffold(
          body: Center(
              child: SizedBox(width: 200, height: 200, child: child))));

  testWidgets('真会话：读到封面就换成内存图，换歌没封面再退回兜底封面', (t) async {
    // 会话还没给封面：用打包进去的兜底封面，不再是那颗小音符图标
    // （用户 2026-11-13 实车反馈：封面位置空白一片）。
    await t
        .pumpWidget(host(MediaArtwork(media: const {'title': 'A'}, demo: false)));
    var image = t.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName, fallbackAsset);

    // MediaSession 送到 artwork（base64）：画内存图。
    await t.pumpWidget(host(MediaArtwork(
        media: const {'title': 'A', 'artwork': pixel}, demo: false)));
    image = t.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect((image.image as MemoryImage).bytes, base64Decode(pixel));

    // 换到另一首、这首没有封面：回到兜底封面，不能停在上一首的图上。
    await t
        .pumpWidget(host(MediaArtwork(media: const {'title': 'B'}, demo: false)));
    image = t.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName, fallbackAsset);
    expect(t.takeException(), isNull);
  });

  testWidgets('坏数据不炸：非法 base64 退回兜底封面', (t) async {
    await t.pumpWidget(host(MediaArtwork(
        media: const {'title': 'A', 'artwork': 'not-base64!!'}, demo: false)));
    final image = t.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, fallbackAsset);
    expect(t.takeException(), isNull);
  });

  testWidgets('示例模式用同一张兜底封面（不读会话）', (t) async {
    await t.pumpWidget(host(MediaArtwork(
        media: const {'title': 'A', 'artwork': pixel}, demo: true)));
    final image = t.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, fallbackAsset);
  });
}
