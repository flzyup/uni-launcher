import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/design_tokens.dart';
import '../theme/launcher_theme.dart';
import 'launcher_dialog.dart';

const standardPickerColors = <Color>[
  Color(0xFFF44336),
  Color(0xFFE91E63),
  Color(0xFF9C27B0),
  Color(0xFF673AB7),
  Color(0xFF3F51B5),
  Color(0xFF2196F3),
  Color(0xFF03A9F4),
  Color(0xFF00BCD4),
  Color(0xFF009688),
  Color(0xFF4CAF50),
  Color(0xFF8BC34A),
  Color(0xFFCDDC39),
  Color(0xFFFFC107),
  Color(0xFFFF9800),
  Color(0xFFFF5722),
  Color(0xFF795548),
  Color(0xFF607D8B),
  Color(0xFF455A64),
];

String colorHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

Future<String?> showCustomColorPicker(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Color initial,
  List<Color> presets = const [],
}) async {
  var hsv = HSVColor.fromColor(initial);
  final input = TextEditingController(text: colorHex(initial));
  final result = await showLauncherSheet<String>(context,
      title: title,
      subtitle: subtitle,
      closeLabel: '关闭取色器',
      width: Design.px(780),
      builder: (context) => StatefulBuilder(builder: (context, setState) {
            final color = hsv.toColor(),
                hex = colorHex(color),
                s = SurfaceStyle.of(context);
            void select(HSVColor value) {
              setState(() {
                hsv = value;
                input.text = colorHex(value.toColor());
                input.selection =
                    TextSelection.collapsed(offset: input.text.length);
              });
            }

            return SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Text('常用颜色',
                      style:
                          TextStyle(fontSize: Design.px(20), color: s.muted)),
                  SizedBox(height: Design.px(14)),
                  Wrap(
                      spacing: Design.px(13),
                      runSpacing: Design.px(13),
                      children: [
                        for (final preset in presets)
                          _ColorSwatch(
                              color: preset,
                              selected: colorHex(preset) == hex,
                              onTap: () => select(HSVColor.fromColor(preset)))
                      ]),
                  SizedBox(height: Design.px(24)),
                  Text('颜色',
                      style:
                          TextStyle(fontSize: Design.px(20), color: s.muted)),
                  SizedBox(height: Design.px(12)),
                  _SaturationValueField(
                      hsv: hsv,
                      onChanged: (saturation, value) => select(
                          hsv.withSaturation(saturation).withValue(value))),
                  SizedBox(height: Design.px(18)),
                  _HueField(
                      hue: hsv.hue,
                      onChanged: (hue) => select(hsv.withHue(hue))),
                  SizedBox(height: Design.px(22)),
                  Row(children: [
                    Container(
                        width: Design.px(58),
                        height: Design.px(58),
                        decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: s.edge))),
                    SizedBox(width: Design.px(18)),
                    Expanded(
                        child: TextField(
                            key: const ValueKey('color-picker-hex'),
                            controller: input,
                            maxLength: 7,
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[#0-9a-fA-F]'))
                            ],
                            decoration: const InputDecoration(
                                counterText: '', labelText: 'HEX 色值'),
                            onSubmitted: (value) {
                              if (RegExp(r'^#[0-9a-fA-F]{6}$')
                                  .hasMatch(value)) {
                                select(HSVColor.fromColor(Color(0xFF000000 |
                                    int.parse(value.substring(1), radix: 16))));
                              }
                            })),
                    SizedBox(width: Design.px(18)),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, hex),
                        child: const Text('应用颜色'))
                  ])
                ]));
          }));
  await Future<void>.delayed(const Duration(milliseconds: 220));
  input.dispose();
  return result;
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorSwatch(
      {required this.color, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => InkResponse(
      key: ValueKey('standard-color-${colorHex(color)}'),
      onTap: onTap,
      radius: Design.px(28),
      child: Container(
          width: Design.px(43),
          height: Design.px(43),
          decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                  color: selected ? Colors.white : Colors.white24,
                  width: selected ? Design.px(3) : Design.px(1))),
          child: selected
              ? const Center(
                  child: Icon(Icons.check, color: Colors.white, size: 18))
              : null));
}

class _SaturationValueField extends StatelessWidget {
  final HSVColor hsv;
  final void Function(double saturation, double value) onChanged;
  const _SaturationValueField({required this.hsv, required this.onChanged});

  @override
  Widget build(BuildContext context) => AspectRatio(
      aspectRatio: 3.2,
      child: LayoutBuilder(builder: (context, box) {
        void update(Offset point) => onChanged(
            (point.dx / box.maxWidth).clamp(0, 1),
            (1 - point.dy / box.maxHeight).clamp(0, 1));
        return GestureDetector(
            key: const ValueKey('saturation-value-field'),
            onTapDown: (event) => update(event.localPosition),
            onPanStart: (event) => update(event.localPosition),
            onPanUpdate: (event) => update(event.localPosition),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(Design.px(12)),
                child: CustomPaint(
                    painter: _SaturationValuePainter(hsv.hue),
                    foregroundPainter: _PickerThumbPainter(Offset(
                        hsv.saturation * box.maxWidth,
                        (1 - hsv.value) * box.maxHeight)))));
      }));
}

class _HueField extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  const _HueField({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) => SizedBox(
      height: Design.px(34),
      child: LayoutBuilder(builder: (context, box) {
        void update(Offset point) =>
            onChanged((point.dx / box.maxWidth).clamp(0, 1) * 360);
        return GestureDetector(
            key: const ValueKey('hue-field'),
            onTapDown: (event) => update(event.localPosition),
            onPanStart: (event) => update(event.localPosition),
            onPanUpdate: (event) => update(event.localPosition),
            child: CustomPaint(
                painter: const _HuePainter(),
                foregroundPainter: _PickerThumbPainter(
                    Offset(hue / 360 * box.maxWidth, box.maxHeight / 2))));
      }));
}

class _SaturationValuePainter extends CustomPainter {
  final double hue;
  const _SaturationValuePainter(this.hue);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(colors: [
            Colors.white,
            HSVColor.fromAHSV(1, hue, 1, 1).toColor()
          ]).createShader(rect));
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black]).createShader(rect));
  }

  @override
  bool shouldRepaint(_SaturationValuePainter old) => old.hue != hue;
}

class _HuePainter extends CustomPainter {
  const _HuePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(Design.px(12))),
        Paint()
          ..shader = const LinearGradient(colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ]).createShader(rect));
  }

  @override
  bool shouldRepaint(_HuePainter old) => false;
}

class _PickerThumbPainter extends CustomPainter {
  final Offset position;
  const _PickerThumbPainter(this.position);
  @override
  void paint(Canvas canvas, Size size) {
    final point = Offset(position.dx.clamp(7, size.width - 7),
        position.dy.clamp(7, size.height - 7));
    canvas.drawCircle(point, Design.px(8),
        Paint()..color = Colors.black.withValues(alpha: .35));
    canvas.drawCircle(
        point,
        Design.px(7),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = Design.px(2));
  }

  @override
  bool shouldRepaint(_PickerThumbPainter old) => old.position != position;
}
