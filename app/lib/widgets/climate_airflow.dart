import 'package:flutter/material.dart';

/// 官方车辆字段使用的方向名称；自动状态不假设具体出风口。
int airflowMask(String? mode) => switch (mode) {
      'defrost' => 1,
      'face' => 2,
      'floor' => 4,
      'face-defrost' => 3,
      'floor-defrost' => 5,
      'floor-face' => 6,
      'all' => 7,
      _ => 0,
    };
String? airflowMode(int mask) => switch (mask) {
      1 => 'defrost',
      2 => 'face',
      3 => 'face-defrost',
      4 => 'floor',
      5 => 'floor-defrost',
      6 => 'floor-face',
      7 => 'all',
      _ => null,
    };
String airflowLabel(String? mode) => switch (mode) {
      'auto' => '自动风向',
      'defrost' => '前挡风',
      'face' => '面部出风',
      'floor' => '脚部出风',
      'face-defrost' => '前挡风和面部',
      'floor-defrost' => '前挡风和脚部',
      'floor-face' => '面部和脚部',
      'all' => '全部出风',
      _ => '风向未知',
    };

class AirflowIcon extends StatelessWidget {
  final String? mode;
  final Color color;
  final double size;
  const AirflowIcon(
      {super.key, required this.mode, required this.color, required this.size});
  @override
  Widget build(BuildContext context) {
    final name = switch (mode) {
      'auto' => 'auto',
      'face' => 'center',
      'floor' => 'bottom',
      'defrost' => 'top',
      'floor-face' => 'center_bottom',
      'floor-defrost' => 'top_bottom',
      'face-defrost' => 'top_center',
      'all' => 'all',
      _ => 'noactive',
    };
    final automatic = mode == 'auto';
    final unknown = name == 'noactive';
    // 所有模式复用 80×80 的人物坐标。自动图的 A 单独绘制，避免原始
    // 128×136 资源的不同透明边距和人物姿态造成跳位。
    final image = Image.asset(
        'assets/icons/airflow/sysui_climate_blow_${automatic || unknown ? 'all' : name}.png',
        width: 80,
        height: 80,
        gaplessPlayback: true,
        color: color,
        colorBlendMode: BlendMode.modulate,
        excludeFromSemantics: true);
    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        child: SizedBox(
          width: 80,
          height: 80,
          child: Stack(children: [
            if (automatic || unknown)
              ClipPath(clipper: const _AirflowPersonClipper(), child: image)
            else
              image,
            if (automatic)
              Positioned(left: 17, top: 27,
                child: Text('A', textScaler: TextScaler.noScaling,
                  style: TextStyle(fontSize: 18, height: 1,
                    color: color, fontWeight: FontWeight.w500))),
          ]),
        ),
      ),
    );
  }
}

/// 保留原车图中的头、躯干及腿部，遮去出风箭头。
class _AirflowPersonClipper extends CustomClipper<Path> {
  const _AirflowPersonClipper();
  @override
  Path getClip(Size size) => Path()
    ..addRect(const Rect.fromLTRB(58, 15, 70, 26))
    ..addRect(const Rect.fromLTRB(39, 28, 64, 45))
    ..addRect(const Rect.fromLTRB(24, 45, 55, 69));
  @override
  bool shouldReclip(_AirflowPersonClipper oldClipper) => false;
}
