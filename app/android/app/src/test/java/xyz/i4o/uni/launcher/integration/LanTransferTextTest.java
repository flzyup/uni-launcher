package xyz.i4o.uni.launcher.integration;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

/**
 * 手机推文本这条链路上不依赖 Context 的那一层：正文清洗、请求体解码。
 * 这里最怕的是把正文改坏（比如把换行吃掉、把中文按错误编码留住），所以逐条钉住。
 */
public class LanTransferTextTest {

    @Test
    public void cleanTextKeepsContentOnlyNormalizesBreaks() {
        assertEquals("第一行\n第二行", LanTransfer.cleanText("第一行\r\n第二行"));
        assertEquals("a\nb", LanTransfer.cleanText("a\rb"));
        assertEquals("前后空白被去掉", LanTransfer.cleanText("  前后空白被去掉  "));
        // 正文里的缩进、空行、中文标点一个都不能动
        // 首尾空白去掉，行内缩进与空行保留\n        assertEquals("缩进\n\n空行留着", LanTransfer.cleanText("  缩进\n\n空行留着  "));
        // 控制字符（\u0000 一类）落盘会把 JSON 写坏，清掉
        assertEquals("ab", LanTransfer.cleanText("a\u0001b"));
        assertEquals("", LanTransfer.cleanText("   "));
        assertEquals("", LanTransfer.cleanText(null));
    }

    @Test
    public void cleanTextTruncatesRunawayInput() {
        StringBuilder big = new StringBuilder();
        for (int i = 0; i < 25000; i++) big.append('字');
        assertEquals(20000, LanTransfer.cleanText(big.toString()).length());
    }

    @Test
    public void decodeTextBodyAcceptsFormJsonAndPlain() {
        assertEquals("取件码 8848",
                LanTransfer.decodeTextBody("text=%E5%8F%96%E4%BB%B6%E7%A0%81+8848"));
        assertEquals("一段话", LanTransfer.decodeTextBody("text=%E4%B8%80%E6%AE%B5%E8%AF%9D"));
        assertEquals("来自 JSON", LanTransfer.decodeTextBody("{\"text\":\"来自 JSON\"}"));
        // 裸文本原样返回（保留换行）
        assertEquals("裸文本\n第二行", LanTransfer.decodeTextBody("裸文本\n第二行"));
        assertEquals("", LanTransfer.decodeTextBody(""));
        assertEquals("", LanTransfer.decodeTextBody(null));
    }

    @Test
    public void decodeTextBodyFallsBackWhenJsonBroken() {
        // 坏 JSON 不吞内容：原样落成一条文本，用户至少能看到自己发的东西
        assertEquals("{not json text=x", LanTransfer.decodeTextBody("{not json text=x"));
    }
}
