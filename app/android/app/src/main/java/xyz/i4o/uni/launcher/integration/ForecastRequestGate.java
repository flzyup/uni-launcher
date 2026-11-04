package xyz.i4o.uni.launcher.integration;

import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Reject results from an earlier request or an earlier adapter lifecycle. */
public final class ForecastRequestGate {
    private long generation;
    private boolean active;

    public void start() { active = true; generation++; UniLog.i(LogTags.WEATHER,"天气请求闸门已启用","generation",generation); }
    public void stop() { active = false; generation++; UniLog.i(LogTags.WEATHER,"天气请求闸门已停用","generation",generation); }
    public long next() { return ++generation; }
    public boolean accepts(long request) {
        if(!active){UniLog.w(LogTags.WEATHER,"天气响应被丢弃：适配器已停止","request",request,"generation",generation);return false;}
        // 被更新的请求取代是正常情况，只在调试级别留痕。
        if(generation!=request){UniLog.d(LogTags.WEATHER,"天气响应被丢弃：已被更新的请求取代","request",request,"generation",generation);return false;}
        return true;
    }
}
