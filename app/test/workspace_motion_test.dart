import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_launcher/model/page_motion.dart';
import 'package:uni_launcher/widgets/page_transition.dart';
import 'package:uni_launcher/widgets/native_slice_builder.dart';

void main() {
  for (final effect in pageEffects.where((e) => e.id != 'none')) {
    testWidgets(
        '${effect.id}: both pages have visible, distinct intermediate transforms',
        (t) async {
      final key = GlobalKey<DesktopPageStackState>();
      final position = ValueNotifier(0.0);
      final selected = <int>[];
      final children = [
        for (var i = 0; i < 3; i++)
          ColoredBox(
              key: ValueKey('probe-$i'),
              color: [Colors.red, Colors.blue, Colors.green][i])
      ];
      await t.pumpWidget(MaterialApp(
          home: Center(
              child: SizedBox(
                  width: 600,
                  height: 300,
                  child: DesktopPageStack(
                      key: key,
                      page: 0,
                      effect: effect.id,
                      position: position,
                      onPageRequested: selected.add,
                      children: children)))));
      final start = t.getRect(find.byKey(const ValueKey('probe-0')));
      key.currentState!.dragStart();
      key.currentState!.dragUpdate(-240);
      await t.pump();
      expect(position.value, closeTo(.4, .001));
      expect(find.byKey(const ValueKey('probe-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('probe-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('probe-2')), findsNothing);
      if (effect.id == 'slide' || effect.id == 'zoom') {
        final outgoing = t.getRect(find.byKey(const ValueKey('probe-0')));
        final incoming = t.getRect(find.byKey(const ValueKey('probe-1')));
        expect(outgoing.left, lessThan(start.left - 180));
        expect(incoming.left, greaterThan(start.left + 300));
        expect(outgoing.right, lessThanOrEqualTo(incoming.left + .1),
            reason: 'no overlapping page content');
        if (effect.id == 'slide') {
          expect(incoming.left - outgoing.right, greaterThan(10),
              reason: 'adjacent pages retain a visible gutter');
        }
        if (effect.id == 'zoom') expect(outgoing.width, lessThan(start.width));
      } else if (effect.id == 'fade') {
        final opacity = find.descendant(
            of: find.byKey(const ValueKey('desktop-motion-page-0')),
            matching: find.byType(Opacity));
        expect(t.widget<Opacity>(opacity).opacity, lessThan(1));
      }
      if (effect.id == 'depth') {
        final clip = t
            .widgetList<ClipRect>(find.descendant(
                of: find.byKey(const ValueKey('desktop-motion-page-0')),
                matching: find.byType(ClipRect)))
            .firstWhere((c) => c.clipper != null);
        expect(clip.clipper!.getClip(const Size(600, 300)),
            const Rect.fromLTWH(0, 0, 360, 300));
      }
      key.currentState!.dragEnd(0);
      await t.pumpAndSettle();
      expect(position.value, 1);
      expect(selected, [1],
          reason: 'slow, sufficiently long drags must change pages');
      expect(find.byKey(const ValueKey('probe-0')), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      position.dispose();
    });
  }

  testWidgets(
      'short and cancelled drags snap back; outer edges never reveal a blank page',
      (t) async {
    final key = GlobalKey<DesktopPageStackState>(),
        position = ValueNotifier(0.0);
    final requested = <int>[];
    await t.pumpWidget(MaterialApp(
        home: SizedBox(
            width: 600,
            child: DesktopPageStack(
                key: key,
                page: 0,
                effect: 'slide',
                position: position,
                onPageRequested: requested.add,
                children: const [Text('first'), Text('second')]))));
    key.currentState!.dragStart();
    key.currentState!.dragUpdate(-80);
    key.currentState!.dragEnd(0);
    await t.pumpAndSettle();
    expect(position.value, 0);
    expect(requested, isEmpty);
    key.currentState!.dragStart();
    key.currentState!.dragUpdate(-500);
    key.currentState!.dragCancel();
    await t.pumpAndSettle();
    expect(position.value, 0);
    expect(requested, isEmpty);
    key.currentState!.dragStart();
    key.currentState!.dragUpdate(900);
    await t.pump();
    expect(position.value, 0);
    key.currentState!.dragEnd(1200);
    await t.pumpAndSettle();
    expect(position.value, 0);
    expect(requested, isEmpty);
    await t.pumpWidget(const SizedBox.shrink());
    position.dispose();
  });

  testWidgets(
      'rapid reversal is continuous and distant page taps paint at most two pages',
      (t) async {
    final position = ValueNotifier(0.0);
    final children = [for (var i = 0; i < 5; i++) Text('page $i')];
    Future<void> show(int page) => t.pumpWidget(MaterialApp(
        home: DesktopPageStack(
            page: page,
            effect: 'slide',
            position: position,
            children: children)));
    await show(0);
    await show(1);
    await t.pump(const Duration(milliseconds: 80));
    final mid = position.value;
    expect(mid, inExclusiveRange(0, 1));
    await show(0);
    expect(position.value, closeTo(mid, .0001));
    await t.pump(const Duration(milliseconds: 32));
    expect(position.value, lessThan(mid));
    await t.pumpAndSettle();
    expect(position.value, 0);
    await show(4);
    await t.pump(const Duration(milliseconds: 80));
    expect(find.text('page 0'), findsOneWidget);
    expect(find.text('page 4'), findsOneWidget);
    for (final i in [1, 2, 3]) {
      expect(find.text('page $i'), findsNothing);
    }
    await t.pumpAndSettle();
    expect(position.value, 4);
    await t.pumpWidget(const SizedBox.shrink());
    position.dispose();
  });

  testWidgets(
      'telemetry bursts rebuild no moving or hidden cards; latest data appears on settle',
      (t) async {
    final state = ValueNotifier<Map<String, dynamic>>({'value': 0});
    final builds = [0, 0, 0];
    final children = [
      for (var i = 0; i < 3; i++)
        NativeSliceBuilder(
            valueListenable: state,
            select: (s) => s['value'],
            builder: (_, s) {
              builds[i]++;
              return Text('$i:${s['value']}');
            })
    ];
    Future<void> show(int page) => t.pumpWidget(MaterialApp(
        home:
            DesktopPageStack(page: page, effect: 'slide', children: children)));
    await show(0);
    await show(1);
    final boundaryBuilds = List.of(builds);
    for (var i = 1; i <= 10; i++) {
      state.value = {'value': i};
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(builds, boundaryBuilds,
        reason: 'no native-data builds during motion');
    await t.pumpAndSettle();
    expect(find.text('1:10'), findsOneWidget);
    expect(builds[0], boundaryBuilds[0]);
    expect(builds[2], boundaryBuilds[2]);
    await t.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
