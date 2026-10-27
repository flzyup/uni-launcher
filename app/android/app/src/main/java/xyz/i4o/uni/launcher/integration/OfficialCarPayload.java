package xyz.i4o.uni.launcher.integration;

import java.io.IOException;

/** Minimal reader for the audited GeelyProto.PublicAttrValue wire contract.
 * Tags: availability=1, format=2, status=3, int32_data=4 (sint32/ZigZag), double_data=5,
 * string_data=6, double_array_data=7, level=8. No OEM implementation is bundled.
 * Preserve raw enums: OEM fromInteger() silently maps unknown values to OFF.
 */
final class OfficialCarPayload {
    Integer availability, format, status, level;
    Number data;
    Long int32Wire;

    boolean active() { return availability != null && availability == 1; }

    Integer integerData() {
        return data instanceof Integer ? data.intValue() : null;
    }

    Double doubleData() {
        if (!(data instanceof Double)) return null;
        double v = data.doubleValue();
        return Double.isNaN(v) || Double.isInfinite(v) ? null : v;
    }

    static OfficialCarPayload parse(byte[] bytes) throws IOException {
        if (bytes == null || bytes.length > 8192) throw new IOException("PA_SIZE");
        Cursor c = new Cursor(bytes);
        OfficialCarPayload result = new OfficialCarPayload();
        while (c.position < bytes.length) {
            long tag = c.varint();
            if (tag <= 0 || tag > 0xffffffffL || (tag >>> 3) == 0)
                throw new IOException("PA_TAG");
            int field = (int) (tag >>> 3), wire = (int) (tag & 7);
            if (field == 1 || field == 2 || field == 3 || field == 4 || field == 8) {
                if (wire != 0) throw new IOException("PA_WIRE");
                long encoded = c.varint();
                if (field != 4 && (encoded < 0 || encoded > Integer.MAX_VALUE))
                    throw new IOException("PA_ENUM_OVERFLOW");
                if (field == 4 && (encoded > 0xffffffffL || encoded < 0))
                    throw new IOException("PA_INT32_OVERFLOW");
                int value = (int) encoded;
                switch (field) {
                    case 1: result.availability = value; break;
                    case 2: result.format = value; break;
                    case 3: result.status = value; break;
                    case 4:
                        // Official PublicAttrValue.dynamicMethod calls readSInt32
                        // (ecarx.adapterapi/code.txt:291631); writeTo uses writeSInt32
                        // (:292078). Only this data field is ZigZag encoded.
                        result.int32Wire = encoded;
                        result.data = Integer.valueOf((int) ((encoded >>> 1) ^ -(encoded & 1)));
                        break;
                    case 8: result.level = value; break;
                    default: break;
                }
            } else if (field == 5) {
                if (wire != 1) throw new IOException("PA_WIRE");
                c.require(8);
                long bits = 0;
                for (int i = 0; i < 8; i++) bits |= (bytes[c.position++] & 255L) << (8 * i);
                result.data = Double.longBitsToDouble(bits);
                result.int32Wire = null;
            } else {
                if (field == 6) {
                    if (wire != 2) throw new IOException("PA_WIRE");
                    // String is the other oneof data case, and replaces numeric data.
                    result.data = null;
                    result.int32Wire = null;
                }
                c.skip(wire);
            }
        }
        return result;
    }

    private static final class Cursor {
        final byte[] bytes;
        int position;
        Cursor(byte[] bytes) { this.bytes = bytes; }
        void require(int count) throws IOException {
            if (count < 0 || count > bytes.length - position) throw new IOException("PA_TRUNCATED");
        }
        long varint() throws IOException {
            long value = 0;
            for (int i = 0; i < 10; i++) {
                require(1);
                int b = bytes[position++] & 255;
                if (i == 9 && (b & 254) != 0) throw new IOException("PA_VARINT");
                value |= (long) (b & 127) << (i * 7);
                if ((b & 128) == 0) return value;
            }
            throw new IOException("PA_VARINT");
        }
        void skip(int wire) throws IOException {
            int count;
            switch (wire) {
                case 0: varint(); return;
                case 1: count = 8; break;
                case 2:
                    long length = varint();
                    if (length < 0 || length > Integer.MAX_VALUE) throw new IOException("PA_LENGTH");
                    count = (int) length;
                    break;
                case 5: count = 4; break;
                default: throw new IOException("PA_WIRE");
            }
            require(count);
            position += count;
        }
    }
}
