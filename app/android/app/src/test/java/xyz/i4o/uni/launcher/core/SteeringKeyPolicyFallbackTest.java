package xyz.i4o.uni.launcher.core;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/**
 * 方控兜底通道不依赖 Context 的那一层：动作→注入键码，以及回环抑制的时间窗。
 *
 * <p>这两条错了后果很具体：键码错会按到别的键（比如快进当上一首），
 * 回环窗错会让一次按键走两步（下一首跳两首）。
 */
public class SteeringKeyPolicyFallbackTest {

    @Test
    public void keyCodeMapsToStandardMediaKeys() {
        assertEquals(SteeringKeyPolicy.MEDIA_NEXT, SteeringKeyPolicy.keyCode("next"));
        assertEquals(SteeringKeyPolicy.MEDIA_PREVIOUS, SteeringKeyPolicy.keyCode("previous"));
        assertEquals(SteeringKeyPolicy.MEDIA_PLAY, SteeringKeyPolicy.keyCode("play"));
        assertEquals(SteeringKeyPolicy.MEDIA_PAUSE, SteeringKeyPolicy.keyCode("pause"));
        // 注入下去的是 AOSP 事件，播放/暂停只能用 85 的切换码，不能用原车码 200085
        assertEquals(SteeringKeyPolicy.MEDIA_PLAY_PAUSE, SteeringKeyPolicy.keyCode("toggle-play"));
        assertEquals(85, SteeringKeyPolicy.keyCode("toggle-play"));
    }

    @Test
    public void keyCodeRefusesActionsWithoutAKey() {
        assertEquals(-1, SteeringKeyPolicy.keyCode("seek"));
        assertEquals(-1, SteeringKeyPolicy.keyCode(""));
        assertEquals(-1, SteeringKeyPolicy.keyCode(null));
    }

    @Test
    public void crossChannelDuplicatesFoldInsideTheirWindow() {
        SteeringKeyPolicy.Debounce debounce = new SteeringKeyPolicy.Debounce();
        long now = 1_000;
        assertTrue(debounce.accept("inject", "next", now));
        // 注入的键从原车回调回来：不同通道、同一分组、窗口内 → 丢掉
        assertFalse(debounce.accept("input", "next", now + 20));
        // 播放在 450 ms 内折叠，换歌只有 150 ms
        assertTrue(debounce.accept("input", "toggle-play", now + 200));
        assertFalse(debounce.accept("session", "toggle-play", now + 500));
    }

    @Test
    public void sameChannelKeepsBothPresses() {
        SteeringKeyPolicy.Debounce debounce = new SteeringKeyPolicy.Debounce();
        long now = 2_000;
        assertTrue(debounce.accept("input", "next", now));
        // 同一个通道连着来两次是用户真的按了两次，不能折叠
        assertTrue(debounce.accept("input", "next", now + 30));
    }

    @Test
    public void unmappedActionsNeverPass() {
        SteeringKeyPolicy.Debounce debounce = new SteeringKeyPolicy.Debounce();
        assertFalse(debounce.accept("input", "volume-up", 3_000));
        assertFalse(debounce.accept("input", "", 3_000));
    }
}
