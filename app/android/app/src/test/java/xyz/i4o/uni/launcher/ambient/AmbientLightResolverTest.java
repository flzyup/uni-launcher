package xyz.i4o.uni.launcher.ambient;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * The vendor ids live in the head unit jar, so the lookup is covered here with
 * stand-in classes. No Android device and no real jar are needed.
 */
public class AmbientLightResolverTest {

    /** Stands in for the vendor constant interface. */
    public interface FakeConstants {
        int SETTING_FUNC_AMBIENCE_LIGHT_COLOR_SET = 0x200A0800;
        int SETTING_FUNC_AMBIENCE_LIGHT_INTERACTIVE_EFFECT = 0x200A0900;
        int BRIGHTNESS_DRIVING_HIGH = 537528066;
    }

    /** Stands in for a vendor enum whose value is exposed by an accessor. */
    public enum FakeLevel {
        HIGH(537528066);

        private final int value;

        FakeLevel(int value) {
            this.value = value;
        }

        public int getValue() {
            return value;
        }
    }

    /** A holder whose nested enum has to be found through the expansion. */
    public static final class FakeHolder {
        public enum Nested {
            HIGH(537527810);

            private final int value;

            Nested(int value) {
                this.value = value;
            }

            public int getValue() {
                return value;
            }
        }
    }

    @Test
    public void resolvesAConstantFromARegisteredRoot() {
        AmbientLightResolver resolver = new AmbientLightResolver();
        resolver.registerRoot(FakeConstants.class);
        assertEquals(Integer.valueOf(0x200A0800),
                resolver.resolve("SETTING_FUNC_AMBIENCE_LIGHT_COLOR_SET"));
        assertEquals(Integer.valueOf(537528066),
                resolver.resolve("BRIGHTNESS_DRIVING_HIGH"));
    }

    @Test
    public void anUnknownNameResolvesToNullAndIsRemembered() {
        AmbientLightResolver resolver = new AmbientLightResolver();
        resolver.registerRoot(FakeConstants.class);
        assertNull(resolver.resolve("SETTING_FUNC_AMBIENCE_LIGHT_NOTHING"));
        List<String> misses = resolver.misses();
        assertEquals(1, misses.size());
        assertEquals("SETTING_FUNC_AMBIENCE_LIGHT_NOTHING", misses.get(0));
    }

    @Test
    public void aFallbackIsUsedOnlyWhenTheNameIsUnknown() {
        AmbientLightResolver resolver = new AmbientLightResolver();
        resolver.registerRoot(FakeConstants.class);
        assertEquals(537528066,
                resolver.resolve("BRIGHTNESS_DRIVING_HIGH", 1));
        assertEquals(1, resolver.resolve("BRIGHTNESS_DRIVING_LOW", 1));
    }

    @Test
    public void anEnumValueIsReadThroughItsAccessor() {
        AmbientLightResolver resolver = new AmbientLightResolver();
        resolver.registerRoot(FakeHolder.class);
        assertEquals(Integer.valueOf(537527810), resolver.resolve("HIGH"));
    }

    @Test
    public void anOverrideStandsInForTheHeadUnitJar() {
        AmbientLightResolver resolver = new AmbientLightResolver();
        Map<String, Integer> values = new HashMap<>();
        values.put("SETTING_FUNC_AMBIENCE_LIGHT_COLOR_SET", 42);
        resolver.setOverride(values);
        assertEquals(Integer.valueOf(42),
                resolver.resolve("SETTING_FUNC_AMBIENCE_LIGHT_COLOR_SET"));
        resolver.setOverride(null);
        assertNull(resolver.resolve("SETTING_FUNC_AMBIENCE_LIGHT_COLOR_SET"));
    }

    @Test
    public void registeringANewRootDropsTheEarlierCache() {
        AmbientLightResolver resolver = new AmbientLightResolver();
        assertNull(resolver.resolve("BRIGHTNESS_DRIVING_HIGH"));
        resolver.registerRoot(FakeConstants.class);
        assertEquals(Integer.valueOf(537528066),
                resolver.resolve("BRIGHTNESS_DRIVING_HIGH"));
    }

    @Test
    public void theContractNamesMatchTheVendorSdk() {
        assertNotNull(AmbientLightContract.FUNC_COLOR_SET);
        assertEquals("SETTING_FUNC_AMBIENCE_LIGHT_COLOR_SET",
                AmbientLightContract.FUNC_COLOR_SET);
        assertEquals(3, AmbientLightContract.ZONE_FUNCTIONS.length);
        assertEquals(AmbientLightContract.FUNC_MAIN_ZONES,
                AmbientLightContract.ZONE_FUNCTIONS[0]);
        assertEquals(AmbientLightContract.FUNC_TOP_ZONES,
                AmbientLightContract.ZONE_FUNCTIONS[1]);
        assertEquals(AmbientLightContract.FUNC_BOT_ZONES,
                AmbientLightContract.ZONE_FUNCTIONS[2]);
        assertTrue("the driving and stationary ladders are different",
                AmbientLightContract.FALLBACK_BRIGHTNESS_LOW
                        != AmbientLightContract.FALLBACK_STATIONARY_LOW);
    }
}
