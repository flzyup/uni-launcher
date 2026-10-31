package xyz.i4o.uni.launcher.ambient;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;

/**
 * Resolves vendor SDK constants by name.
 *
 * <p>The head unit jar is never linked against by this project, so every
 * vendor id is read reflectively. A name that cannot be resolved returns
 * null; it is never replaced by a guessed number, because writing a guessed
 * value into a different function is worse than not writing at all.
 *
 * <p>Resolution order:
 * <ol>
 *   <li>classes registered as roots, expanded through nested classes and
 *       implemented interfaces (the {@code ICarFunction} handle's own class is
 *       the most accurate source, because the constants live in the same jar);</li>
 *   <li>the audited constant interfaces in
 *       {@link AmbientLightContract#CONSTANT_CLASSES}.</li>
 * </ol>
 *
 * <p>Within a class a constant is looked up as a static field first and as an
 * enum constant second. An enum has no numeric value of its own, so its
 * accessor is used; the ordinal is never used as a substitute.
 *
 * <p>This class has no Android dependency, so the whole lookup is covered by
 * plain JVM unit tests.
 */
public final class AmbientLightResolver {
    /** Accessors that may expose the numeric value of an enum constant. */
    private static final String[] ENUM_VALUE_ACCESSORS = {
        "getValue", "getZone", "getCode", "getId", "getArea", "getType", "value"
    };

    private final LinkedHashSet<Class<?>> roots = new LinkedHashSet<>();
    private final Map<String, Integer> cache = new HashMap<>();
    private final List<String> misses = new ArrayList<>();
    private Map<String, Integer> override;

    /**
     * Registers a runtime class as the most accurate lookup root.
     *
     * <p>The {@code ICarFunction} handle's class is the best source: the
     * constants are packaged in the same jar. Registering a new root drops
     * the cache, because an earlier lookup may have been incomplete.
     */
    public synchronized void registerRoot(Class<?> root) {
        if (root == null || !roots.add(root)) return;
        cache.clear();
        misses.clear();
    }

    /** Drops every cached lookup and every registered root. */
    public synchronized void invalidate() {
        cache.clear();
        misses.clear();
        roots.clear();
        override = null;
    }

    /**
     * Overrides the resolution result, used by unit tests to stand in for the
     * head unit jar.
     *
     * @param values name to value, or null to restore normal resolution
     */
    public synchronized void setOverride(Map<String, Integer> values) {
        this.override = values;
        cache.clear();
    }

    /** Names that could not be resolved, in the order they were missed. */
    public synchronized List<String> misses() {
        return new ArrayList<>(misses);
    }

    /**
     * Resolves a constant by name.
     *
     * @return the value, or null when the name is unknown
     */
    public synchronized Integer resolve(String name) {
        if (name == null || name.isEmpty()) return null;
        if (override != null) return override.get(name);
        if (cache.containsKey(name)) return cache.get(name);
        Integer hit = null;
        for (Class<?> candidate : searchClasses()) {
            Integer value = lookupIn(candidate, name);
            if (value != null) {
                hit = value;
                break;
            }
        }
        cache.put(name, hit);
        if (hit == null && !misses.contains(name)) misses.add(name);
        return hit;
    }

    /**
     * Resolves a constant by name, falling back to {@code fallback} when the
     * name is unknown.
     */
    public synchronized int resolve(String name, int fallback) {
        Integer value = resolve(name);
        return value == null ? fallback : value;
    }

    // ----------------------------------------------------------------- internals

    /** Candidate classes: registered roots first, then the audited list. */
    private List<Class<?>> searchClasses() {
        LinkedHashSet<Class<?>> out = new LinkedHashSet<>();
        for (Class<?> root : roots) expand(root, out, 2);
        for (String name : AmbientLightContract.CONSTANT_CLASSES) {
            Class<?> cls;
            try {
                cls = Class.forName(name);
            } catch (ClassNotFoundException | LinkageError missing) {
                continue;
            }
            expand(cls, out, 1);
        }
        return new ArrayList<>(out);
    }

    /** Expands a class into itself, its nested classes and its interfaces. */
    private void expand(Class<?> cls, LinkedHashSet<Class<?>> out, int depth) {
        if (!out.add(cls) || depth <= 0) return;
        Class<?>[] nested;
        try {
            nested = cls.getDeclaredClasses();
        } catch (Throwable ignored) {
            nested = new Class<?>[0];
        }
        for (Class<?> item : nested) expand(item, out, depth - 1);
        Class<?>[] interfaces;
        try {
            interfaces = cls.getInterfaces();
        } catch (Throwable ignored) {
            interfaces = new Class<?>[0];
        }
        for (Class<?> item : interfaces) expand(item, out, depth - 1);
    }

    /** Finds a constant with this name inside one class. */
    private Integer lookupIn(Class<?> cls, String name) {
        Field field = null;
        try {
            field = cls.getField(name);
        } catch (NoSuchFieldException ignored) {
            try {
                field = cls.getDeclaredField(name);
            } catch (NoSuchFieldException alsoMissing) {
                field = null;
            }
        }
        if (field != null) {
            try {
                field.setAccessible(true);
            } catch (Throwable ignored) {
                // A hidden-API block only means the constant stays unreadable.
            }
            try {
                Integer value = toInt(field.get(null));
                if (value != null) return value;
            } catch (Throwable ignored) {
                // Fall through to the enum lookup.
            }
        }
        Object[] constants;
        try {
            constants = cls.getEnumConstants();
        } catch (Throwable ignored) {
            constants = null;
        }
        if (constants != null) {
            for (Object constant : constants) {
                if (constant instanceof Enum<?> && name.equals(((Enum<?>) constant).name())) {
                    Integer value = enumInt(constant);
                    if (value != null) return value;
                }
            }
        }
        return null;
    }

    /** Converts a field value to an int, or null when it is not numeric. */
    private Integer toInt(Object value) {
        if (value instanceof Integer) return (Integer) value;
        if (value instanceof Short) return ((Short) value).intValue();
        if (value instanceof Byte) return ((Byte) value).intValue();
        if (value instanceof Long) return ((Long) value).intValue();
        if (value instanceof Enum<?>) return enumInt(value);
        return null;
    }

    /**
     * Reads the numeric value of an enum constant through its accessor.
     *
     * <p>The ordinal is never used: it says nothing about the value the
     * vendor expects on the wire.
     */
    private Integer enumInt(Object constant) {
        Class<?> cls = constant.getClass();
        for (String name : ENUM_VALUE_ACCESSORS) {
            try {
                Method method = cls.getMethod(name);
                if (method.getReturnType() != int.class
                        && method.getReturnType() != Integer.class) continue;
                Object value = method.invoke(constant);
                Integer converted = toInt(value);
                if (converted != null) return converted;
            } catch (Throwable ignored) {
                // Try the next accessor.
            }
        }
        return null;
    }
}
