import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'glass_surface.dart';

/// 设计稿 `.blk`：分组块。
///
/// ```css
/// .blk{border:1px solid rgba(ink,.07);border-radius:18px;padding:12px 17px 14px;
///      background:rgba(ink,.02);margin-bottom:11.67px}
/// .blk .bt{font-size:19px;font-weight:500}
/// .blk .bn{font-size:12.5px;color:rgba(ink,.4);margin-top:3px;margin-bottom:10px}
/// ```
///
/// 两处容易写错、之前就写错了：
/// 1. **说明在标题正下方**（12.5 号、白 40%），不是右对齐挂在标题旁边；
///    `trailing` 才是标题行右端那一小块（「已安装 3 套」「查看全部 24」）。
/// 2. 暗夜的面是**平的 2% 白**，没有玻璃高光、没有外投影——那是桌面卡片的
///    画法，设置页的块一直比稿子「厚」就是这里来的。
class SettingBlock extends StatelessWidget {
  /// 可以为空：f13 的第二、三块在设计稿里只有内容、没有标题行。
  final String? title;
  final String? note;
  final Widget? trailing;
  final Widget child;

  /// 设计稿里被单独收紧过的块（f9「外观与壁纸」、f38「仪表投屏」）用它：
  /// 内边距默认 10/11，标题与内容的间距也从 10 收到 8。
  ///
  /// 这两页都是「一屏必须放完」的长表单——多出来的两三个像素不会被人看见，
  /// 但十来个块各让 2px，就是底部能少切掉一整行说明。
  final bool dense;
  final EdgeInsetsGeometry? padding;
  const SettingBlock(
      {super.key,
      this.title,
      this.note,
      this.trailing,
      required this.child,
      this.dense = false,
      this.padding});

  @override
  Widget build(BuildContext context) {
    final s = SurfaceStyle.of(context);
    final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                  child: Text(title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.dz(19),
                          fontWeight: FontWeight.w500))),
              if (trailing != null) trailing!
            ]),
          if (note != null)
            Padding(
                padding: EdgeInsets.only(top: Design.dz(3)),
                child: Text(note!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: Design.dz(12.5), color: s.muted))),
          if (title != null) SizedBox(height: Design.dz(dense ? 8 : 10)),
          child
        ]);
    final pad = padding ??
        EdgeInsets.fromLTRB(Design.dz(17), Design.dz(dense ? 10 : 12),
            Design.dz(17), Design.dz(dense ? 11 : 14));
    if (!s.nocturne) {
      // 经典/玻璃皮肤沿用玻璃材质：这两套没有「平面块」的设定，
      // 换掉会让原来的层次塌掉。
      return GlassSurface(padding: pad, child: body);
    }
    return DecoratedBox(
        decoration: BoxDecoration(
            color: s.text.withValues(alpha: .02),
            borderRadius: BorderRadius.circular(s.radius),
            border: Border.all(color: s.text.withValues(alpha: .07))),
        child: Padding(padding: pad, child: body));
  }
}
