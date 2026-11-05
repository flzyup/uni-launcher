package xyz.i4o.uni.launcher.integration;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

/**
 * TV 通道里不碰网络的那一层：签名、轮询判定、错误文案、列表归一化。
 * 签名向量是算好的定值，改错一个字节就会红。
 */
public class QuarkPanTest {

    @Test
    public void reqIdIsMd5OfDeviceAndTimestamp() {
        assertEquals("6425c374c9a5fbd57a354385aa9ac0c6",
                QuarkPan.reqId("dev", "1700000000000"));
        assertEquals(32, QuarkPan.reqId("", "1").length());
    }

    @Test
    public void signIsSha256OfMethodPathTsAndKey() {
        String key = "kw2dvtd7p4t3pjl2d9ed9yc8yej8kw2d";
        assertEquals("e53de2f42449ceebfb3883f66973c179a1d3c354335d2d4360baea00f4180e7b",
                QuarkPan.sign("GET", "/oauth/authorize", "1700000000000", key));
        assertEquals("c28e16e6112ae2e998221c1e67ac9013f4982dbb8e42c4ca32fb8b3d6944c4f3",
                QuarkPan.sign("GET", "/file", "1700000000000", key));
        assertEquals(64, QuarkPan.sign("POST", "/token", "1", key).length());
    }

    @Test
    public void deviceIdIsStableLength() {
        String id = QuarkPan.newDeviceId();
        assertEquals(32, id.length());
        assertFalse(id.contains("-"));
        assertEquals(32, QuarkPan.newDeviceId().length());
    }

    @Test
    public void pollVerdictWaitsUntilConfirmed() {
        // 未扫码/未确认：HTTP 400 + errno 11003，必须继续等而不是报错
        assertEquals("wait", QuarkPan.pollVerdict(400, 11003, "", "用户未确认授权"));
        assertEquals("wait", QuarkPan.pollVerdict(400, 0, "", ""));
        // 拿到 code 才是成功
        assertEquals("code", QuarkPan.pollVerdict(200, 0, "abc123", ""));
        // 过期与失效要分开
        assertEquals("expired", QuarkPan.pollVerdict(400, 11002, "", "二维码已过期"));
        assertEquals("expired", QuarkPan.pollVerdict(400, 0, "", "登录请求已过期"));
        assertEquals("error", QuarkPan.pollVerdict(200, 11004, "", "授权码无效"));
    }

    @Test
    public void errorTextIsUserFacingChinese() {
        assertEquals("等待手机确认授权", QuarkPan.errorText(400, 11003, "用户未确认授权"));
        assertEquals("二维码已过期，请刷新", QuarkPan.errorText(400, 11002, ""));
        assertEquals("授权码无效，请重新扫码", QuarkPan.errorText(200, 11004, ""));
        assertEquals("夸克登录已失效，请重新扫码", QuarkPan.errorText(401, 11001, ""));
        assertEquals("夸克服务暂时不可用（HTTP 502）", QuarkPan.errorText(502, 0, ""));
        assertEquals("", QuarkPan.errorText(200, 0, ""));
    }

    @Test
    public void tokenBrokenDetectsExpiredAccessToken() {
        assertTrue(QuarkPan.tokenBroken(11001, ""));
        assertTrue(QuarkPan.tokenBroken(0, "access_token is invalid"));
        assertTrue(QuarkPan.tokenBroken(0, "token 无效"));
        assertFalse(QuarkPan.tokenBroken(11003, "用户未确认授权"));
        assertFalse(QuarkPan.tokenBroken(0, ""));
    }

    @Test
    public void htmlUnescapeRestoresNames() {
        assertEquals("A & B", QuarkPan.htmlUnescape("A &amp; B"));
        assertEquals("<script>", QuarkPan.htmlUnescape("&lt;script&gt;"));
        assertEquals("", QuarkPan.htmlUnescape(null));
    }

    @Test
    public void fieldReadsTopLevelAndNested() throws Exception {
        // /oauth/authorize 的字段在顶层
        JSONObject authorize = new JSONObject()
                .put("status", 0)
                .put("qr_data", "iVBORw0KGgo=")
                .put("query_token", "sta-abc");
        assertEquals("iVBORw0KGgo=", QuarkPan.field(authorize, "qr_data"));
        assertEquals("sta-abc", QuarkPan.field(authorize, "query_token"));
        // /file 与 token 端点在 data 里
        JSONObject nested = new JSONObject()
                .put("status", 0)
                .put("data", new JSONObject().put("download_url", "https://x/1"));
        assertEquals("https://x/1", QuarkPan.field(nested, "download_url"));
        assertEquals("", QuarkPan.field(nested, "qr_data"));
        assertEquals("", QuarkPan.field(null, "qr_data"));
    }

    @Test
    public void normalizeEntriesUsesTvFieldNames() throws Exception {
        JSONArray raw = new JSONArray();
        raw.put(new JSONObject().put("fid", "f1").put("filename", "电影 &amp; 合集")
                .put("isdir", 1).put("size", 0).put("updated_at", 1700000000000L));
        raw.put(new JSONObject().put("filename", "缺 fid"));
        raw.put((Object) null);
        raw.put(new JSONObject().put("fid", "f2").put("filename", "").put("size", 4096));
        JSONArray out = QuarkPan.normalizeEntries(raw);
        assertEquals(2, out.length());
        assertEquals("电影 & 合集", out.optJSONObject(0).optString("name"));
        assertTrue(out.optJSONObject(0).optBoolean("dir"));
        assertEquals("(未命名)", out.optJSONObject(1).optString("name"));
        assertFalse(out.optJSONObject(1).optBoolean("dir"));
        assertEquals(4096L, out.optJSONObject(1).optLong("size"));
        assertEquals(0, QuarkPan.normalizeEntries(null).length());
    }
}
