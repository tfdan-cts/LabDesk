import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/mobile/background_grace.dart';

void main() {
  final t0 = DateTime(2026, 9, 5, 12, 0, 0);
  const grace = Duration(seconds: 20);

  test('a session in the foreground is never due to close', () {
    final watch = BackgroundGrace(grace: grace);

    expect(watch.isBackgrounded, isFalse);
    expect(watch.isDue(t0), isFalse);
    expect(watch.isDue(t0.add(const Duration(hours: 3))), isFalse);
  });

  test('a backgrounded session is not due until the grace has run out', () {
    final watch = BackgroundGrace(grace: grace)..onBackground(t0);

    expect(watch.isBackgrounded, isTrue);
    expect(watch.isDue(t0), isFalse);
    expect(watch.isDue(t0.add(const Duration(seconds: 19))), isFalse);
    expect(watch.isDue(t0.add(grace)), isTrue);
    expect(watch.isDue(t0.add(const Duration(minutes: 5))), isTrue);
  });

  test('coming back before the grace runs out cancels it', () {
    final watch = BackgroundGrace(grace: grace)..onBackground(t0);
    watch.onForeground();

    expect(watch.isBackgrounded, isFalse);
    expect(
      watch.isDue(t0.add(const Duration(minutes: 5))),
      isFalse,
      reason: 'the operator came back, so the clock that was running is gone',
    );
  });

  test('backgrounding again restarts the grace from the later moment', () {
    final watch = BackgroundGrace(grace: grace)..onBackground(t0);
    watch.onForeground();
    final later = t0.add(const Duration(minutes: 5));
    watch.onBackground(later);

    expect(watch.isDue(later.add(const Duration(seconds: 5))), isFalse);
    expect(watch.isDue(later.add(grace)), isTrue);
  });

  test('a clock that goes backwards does not close a live session', () {
    final watch = BackgroundGrace(grace: grace)..onBackground(t0);

    expect(
      watch.isDue(t0.subtract(const Duration(minutes: 1))),
      isFalse,
      reason: 'a negative elapsed time is not a grace that has run out',
    );
  });

  test('the remaining grace is reported so a timer can be set for it', () {
    final watch = BackgroundGrace(grace: grace);

    expect(watch.remaining(t0), Duration.zero,
        reason: 'nothing is pending in the foreground');

    watch.onBackground(t0);
    expect(watch.remaining(t0), grace);
    expect(watch.remaining(t0.add(const Duration(seconds: 15))),
        const Duration(seconds: 5));
    expect(watch.remaining(t0.add(const Duration(minutes: 1))), Duration.zero);
  });
}
