import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/traffic_countdown.dart';
import 'package:uni_launcher/model/traffic_light.dart';

/// 红绿灯读秒**显示**状态机单测。
///
/// 背景：真车实测绿灯时读秒**一直在 3 与 2 之间来回跳**。
/// 根因是旧算法每收到一帧就把读秒**重新锚回原始值**，而高德不是每秒都刷
/// 这个字段（真车帧间隔约 2 秒）——于是显示变成
/// `3 →（本机减 1）2 →（新帧重锚）3 → 2 …` 的锯齿。
///
/// 这里锁死的新规则：**同一灯态里读秒只减不增。**
/// 用例移植自 cardesk `TrafficCountdownTest.kt`。
void main() {
  const green = 'green', red = 'red';

  group('基本', () {
    test('第一帧直接用原始读秒当锚点', () {
      final t = TrafficCountdown();
      expect(t.accept(green, 9, 0), 9);
      expect(t.current(0), 9);
    });

    test('没有新帧时按本机时钟往下减', () {
      final t = TrafficCountdown()..accept(green, 9, 0);
      expect(t.current(1000), 8);
      expect(t.current(2000), 7);
      expect(t.current(3000), 6);
    });

    test('current 不推进状态', () {
      final t = TrafficCountdown()..accept(green, 9, 0);
      expect(t.current(1000), 8);
      expect(t.current(1000), 8);
      expect(t.current(1000), 8);
    });

    test('归零之后停在 0，不画「—」', () {
      // 巡航绿灯最后 3 秒是「黄环 + 读秒」，归零那一下如果换成「—」，
      // 看起来就是「变黄了却没有倒计时」（用户 2026-11-20 报的问题）。
      final t = TrafficCountdown()..accept(green, 2, 0);
      expect(t.current(1000), 1);
      expect(t.current(2000), 0);
      expect(t.current(9000), 0);
    });
  });

  group('本轮的核心回归：不回跳', () {
    // 真车症状的复现：原始读秒恒定（供应商没刷新），帧间隔 2 秒。
    // 旧算法会显示成 3 → 2 → 3 → 2 …；新算法必须单调递减直到归零。
    test('原始值恒定且帧间隔 2 秒时读秒单调递减不回跳', () {
      final t = TrafficCountdown();
      final shown = <int?>[];
      for (var frame = 0; frame <= 4; frame++) {
        final at = frame * 2000;
        shown.add(t.accept(green, 3, at));
        shown.add(t.current(at + 1000));
      }
      final numbers = shown.whereType<int>().toList();
      for (var i = 1; i < numbers.length; i++) {
        expect(numbers[i] <= numbers[i - 1], isTrue,
            reason: '读秒不能回跳，实际序列：$shown');
      }
      expect(numbers.first, 3);
      expect(numbers.contains(1), isTrue, reason: '应该能走到 1 秒，实际：$numbers');
    });

    test('新帧的原始值没变时不会把已经走掉的秒数加回去', () {
      final t = TrafficCountdown();
      expect(t.accept(green, 3, 0), 3);
      // 两秒后同一灯态又来一帧，原始值还是 3：本机已经减到 1，不能被重锚回 3。
      expect(t.accept(green, 3, 2000), 1);
    });

    test('新帧的原始值更小时以它为准', () {
      final t = TrafficCountdown()..accept(green, 12, 0);
      expect(t.accept(green, 5, 3000), 5);
    });

    test('供应商把秒数加回去时显示值不跟着涨', () {
      final t = TrafficCountdown()..accept(green, 5, 0);
      expect(t.current(1000), 4);
      expect(t.accept(green, 9, 2000)!, lessThanOrEqualTo(4));
    });

    test('归零之后同一读数重复推上来不复活', () {
      final t = TrafficCountdown()..accept(green, 2, 0);
      expect(t.current(2000), 0);
      expect(t.accept(green, 2, 3000), 0);
      expect(t.current(4000), 0);
      expect(t.expired, isTrue);
    });

    test('归零之后供应商报了一个新读数就重起一轮', () {
      // 巡航换灯 / 换路口时灯色可能还是 green，读数是新的：不认它就会一直
      // 卡在 0（用户看到的「整段没倒计时」）。
      final t = TrafficCountdown()..accept(green, 2, 0);
      expect(t.current(2000), 0);
      expect(t.expiredAt(2000), isTrue);
      expect(t.accept(green, 7, 3000), 7);
      expect(t.expired, isFalse);
      expect(t.current(4000), 6);
    });
  });

  group('巡航绿灯最后几秒（2026-11-21 回归）', () {
    /// 真车帧序：绿灯正常递减到最后几秒时，供应商把这个字段改报 **0**
    /// （不是「还剩 0 秒」，是「这一帧不给了」），并且会连着好几帧。
    /// 要求：黄环从剩余 3 秒开始，数字照常 3 → 2 → 1 → 0，不许提前钉在 0。
    test('供应商连着报 0 时，黄灯期间的读秒是 3、2、1、0', () {
      final t = TrafficCountdown()..accept(green, 5, 0);
      final amber = <int>[];
      for (var ms = 1000; ms <= 5000; ms += 1000) {
        // 3 秒起供应商改报 0（真车就是这么干的）。
        t.accept(green, ms >= 3000 ? 0 : null, ms);
        final shown = t.current(ms);
        final lamp = trafficLampFor(green, shown,
            expired: t.expiredAt(ms));
        if (lamp == 'amber') amber.add(shown!);
      }
      expect(amber, [3, 2, 1, 0],
          reason: '黄灯期间必须逐秒 3→2→1→0，实际：$amber');
    });

    test('报 0 之后灯态变了就重起一轮，不继承旧读数', () {
      final t = TrafficCountdown()..accept(green, 2, 0);
      t.accept(green, 0, 1000);
      t.accept(green, 0, 3000);
      expect(t.current(3000), 0);
      // 红灯来了，读数按新的算
      expect(t.accept(red, 40, 4000), 40);
      expect(t.expired, isFalse);
    });

    /// 真车 2026-11-21 14:09:12：左转 `green@4` 之后下一帧直接 `green@0`，
    /// 3、2、1 全被跳过；这一行信号**正好 3.0 秒**才被下一组换掉。
    /// 按「只是没读数」处理，本机时钟从 4 慢慢数，数到 2 就被换掉 ——
    /// 用户看到「黄 3、黄 2，然后整行消失」，永远见不到 1、0。
    test('读数从 4 跳到 0 时，黄灯补齐 3、2、1、0', () {
      final t = TrafficCountdown()..accept(green, 4, 0);
      // 100ms 后供应商改口报 0（相位结束）
      expect(t.accept(green, 0, 100), 3, reason: '要压到 3 秒重新起跑');
      final amber = <int>[];
      for (var ms = 1100; ms <= 3100; ms += 1000) {
        final shown = t.current(ms);
        final lamp = trafficLampFor(green, shown, expired: t.expiredAt(ms));
        expect(lamp, 'amber', reason: '$ms 时应该已经是黄灯');
        amber.add(shown!);
      }
      expect(amber, [2, 1, 0], reason: '黄灯必须走完 2、1、0，实际：$amber');
    });

    test('本机已经在 3 秒以内时报 0，数字不往回抬', () {
      final t = TrafficCountdown()..accept(green, 5, 0);
      expect(t.accept(green, null, 2000), 3, reason: '没读数，本机走到 3');
      expect(t.accept(green, 0, 2100), 3, reason: '已经是 3 秒，压缩不该让它重新数一遍');
      expect(t.current(3100), 2);
    });

    test('连着报 0 只压一次，不会反复重锚', () {
      final t = TrafficCountdown()..accept(green, 4, 0);
      expect(t.accept(green, 0, 100), 3);
      // 重复推同一个 0 不是新信息
      expect(t.accept(green, 0, 1200), 2);
      expect(t.accept(green, 0, 2200), 1);
      expect(t.current(3200), 0);
    });

    /// 真车巡航帧间隔约 1.5 秒。旧写法每来一帧就把时钟原点挪到这一帧，
    /// `~/ 1000` 把不足 1 秒的余量丢掉 → 每个数字多停 0.5 秒，整段黄灯
    /// 能拖到 3.5 秒，末尾的 0 就被挤到信号行消失之后（用户 2026-11-21
    /// 看到的「数到 1 就没了」）。
    test('帧间隔 1.5 秒时每个数字仍准准占 1 秒', () {
      final t = TrafficCountdown()..accept(green, 6, 0);
      for (var ms = 1500; ms <= 6000; ms += 1500) {
        t.accept(green, null, ms);
      }
      expect(t.current(2999), 4);
      expect(t.current(3000), 3, reason: '3 秒才转黄');
      expect(t.current(3999), 3);
      expect(t.current(4000), 2);
      expect(t.current(5000), 1);
      expect(t.current(6000), 0);
      expect(t.expiredAt(6000), isTrue);
    });

    test('读数没变的帧不挪时钟原点，lastAnchorAt 却要跟着走', () {
      final t = TrafficCountdown()..accept(green, 9, 0);
      t.accept(green, 9, 1500); // 供应商没刷新，重复推 9
      expect(t.current(1500), 8,
          reason: '按本机时钟走（1.5 秒只掉 1 秒），不能因为重复帧把 9 重新锚一遍');
      expect(t.lastAnchorAt, 1500, reason: 'TTL 判活要用最后一帧的时刻');
    });

    test('红灯报 0 不压秒（黄灯序列只管绿灯）', () {
      final t = TrafficCountdown()..accept(red, 30, 0);
      expect(t.accept(red, 0, 1000), 29);
      expect(t.current(5000), 25);
    });
  });

  group('灯态切换', () {
    test('灯态变了重新起一轮', () {
      final t = TrafficCountdown()..accept(green, 3, 0);
      expect(t.accept(red, 25, 5000), 25);
      expect(t.current(6000), 24);
    });

    test('灯态变了之后旧的归零状态不跟着过来', () {
      final t = TrafficCountdown()..accept(green, 1, 0);
      expect(t.current(1000), 0);
      expect(t.accept(red, 20, 2000), 20);
      expect(t.expired, isFalse);
    });
  });

  group('缺读秒 / 归零', () {
    test('这一帧没带读秒时沿用上一帧的值继续减', () {
      final t = TrafficCountdown()..accept(green, 6, 0);
      expect(t.accept(green, null, 1000), 5);
      expect(t.current(2000), 4);
    });

    test('灯态没变、也从没带过读秒时不显示数字', () {
      final t = TrafficCountdown()..accept(green, null, 0);
      expect(t.current(0), isNull);
      expect(t.expired, isFalse, reason: '没带读秒不等于归零，绿灯不该转黄');
    });

    test('供应商报 0 当成「这一帧没读数」，不当成归零', () {
      // 巡航绿灯最后几秒会连着报 0（真车日志 14 个绿灯周期有 11 个以
      // green@0 收尾）。当成归零处理，读秒会提前钉死在 0，最后 3 秒就成了
      // 「黄环 + 0」—— 用户 2026-11-21 报的就是这个。
      final t = TrafficCountdown()..accept(green, 0, 0);
      expect(t.current(0), isNull, reason: '没给过正数，就没有依据');
      expect(t.expired, isFalse, reason: '报 0 不等于归零');
    });

    test('reset 之后从头开始', () {
      final t = TrafficCountdown()..accept(green, 3, 0);
      t.reset();
      expect(t.current(1000), isNull);
      expect(t.accept(red, 8, 2000), 8);
    });

    test('lastAnchorAt 报告上一次收到信号的时刻', () {
      final t = TrafficCountdown();
      expect(t.lastAnchorAt, 0);
      t.accept(green, 3, 1234);
      expect(t.lastAnchorAt, 1234);
      t.reset();
      expect(t.lastAnchorAt, 0);
      expect(t.anchored, isFalse);
    });
  });

  group('重绘节拍', () {
    test('下一次跳变是整秒，不是归零那一刻', () {
      final t = TrafficCountdown()..accept(green, 9, 0);
      expect(t.nextTickMs(0), 1000);
      expect(t.nextTickMs(1200), 2000);
      expect(t.nextTickMs(8999), 9000);
    });

    test('锚点落在任意毫秒时跳变跟着锚点走', () {
      final u = TrafficCountdown()..accept(green, 9, 350);
      expect(u.nextTickMs(350), 1350);
      expect(u.nextTickMs(4000), 4350);
    });

    test('没有读秒时没有跳变时刻', () {
      final t = TrafficCountdown()..accept(green, null, 0);
      expect(t.nextTickMs(0), isNull);
    });
  });

  group('归零判断', () {
    test('读数自己走到 0 也算走完（不需要等新包）', () {
      final t = TrafficCountdown()..accept(green, 2, 0);
      expect(t.expiredAt(1000), isFalse);
      expect(t.expiredAt(2500), isTrue);
    });

    test('从没带过读秒不算走完', () {
      final t = TrafficCountdown()..accept(green, null, 0);
      expect(t.expiredAt(99000), isFalse);
    });
  });

  group('绿灯最后 3 秒转黄', () {
    test('剩余 4 秒还是绿、3 秒转黄', () {
      expect(trafficLampFor(green, 4), green);
      expect(trafficLampFor(green, 3), 'amber');
      expect(trafficLampFor(green, 1), 'amber');
    });

    test('归零后保持黄灯，但没带读秒时保持绿灯', () {
      expect(trafficLampFor(green, null, expired: true), 'amber');
      expect(trafficLampFor(green, null), green);
    });

    test('红灯和其他灯态一律原样', () {
      expect(trafficLampFor(red, 1), red);
      expect(trafficLampFor('unknown', null, expired: true), 'unknown');
    });
  });
}
