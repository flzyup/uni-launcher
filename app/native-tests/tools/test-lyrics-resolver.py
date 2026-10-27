#!/usr/bin/env python3
"""Local lyric-resolver contract tests with JVM doubles; no device and no network."""
from pathlib import Path
import os, subprocess, tempfile

def jdk(name):
    home = os.environ.get("JAVA_HOME") or os.environ.get("JDK_HOME")
    suffix = ".exe" if os.name == "nt" else ""
    if home:
        candidate = Path(home) / "bin" / (name + suffix)
        if candidate.exists():
            return str(candidate)
    return name

temporary = tempfile.TemporaryDirectory(prefix="uni-lyrics-contract-")
root = Path(temporary.name)
stubs = root / "stubs"

files = {
"android/os/Looper.java": '''
package android.os; public class Looper { public static Looper getMainLooper(){return new Looper();} }''',
"android/os/Handler.java": '''
package android.os; public class Handler { public Handler(Looper looper){} public boolean post(Runnable action){action.run();return true;} }''',
"android/util/Base64.java": '''
package android.util; public class Base64 {
  public static final int DEFAULT=0,NO_WRAP=2;
  public static byte[] decode(String value,int flags){return java.util.Base64.getMimeDecoder().decode(value);} }''',
"org/json/JSONException.java": '''
package org.json; public class JSONException extends Exception { public JSONException(String message){super(message);} }''',
"org/json/Parser.java": '''
package org.json; import java.util.*;
final class Parser {
  private final String s; private int i;
  static Object parse(String text) throws JSONException {
    Parser p=new Parser(text); Object value=p.value(); p.space();
    if(p.i<p.s.length()) throw new JSONException("trailing");
    return value;
  }
  private Parser(String text){ s=text; }
  private void space(){ while(i<s.length()&&Character.isWhitespace(s.charAt(i))) i++; }
  private Object value() throws JSONException {
    space(); if(i>=s.length()) throw new JSONException("eof");
    char c=s.charAt(i);
    if(c=='{') return object();
    if(c=='[') return array();
    if(c=='"') return string();
    if(s.startsWith("true",i)){ i+=4; return Boolean.TRUE; }
    if(s.startsWith("false",i)){ i+=5; return Boolean.FALSE; }
    if(s.startsWith("null",i)){ i+=4; return null; }
    return number();
  }
  private Map<String,Object> object() throws JSONException {
    Map<String,Object> map=new LinkedHashMap<>(); i++; space();
    if(i<s.length()&&s.charAt(i)=='}'){ i++; return map; }
    while(true){
      space(); String key=string(); space();
      if(s.charAt(i++)!=':') throw new JSONException("colon");
      map.put(key,value()); space();
      char c=s.charAt(i++);
      if(c=='}') return map;
      if(c!=',') throw new JSONException("comma");
    }
  }
  private List<Object> array() throws JSONException {
    List<Object> list=new ArrayList<>(); i++; space();
    if(i<s.length()&&s.charAt(i)==']'){ i++; return list; }
    while(true){
      list.add(value()); space();
      char c=s.charAt(i++);
      if(c==']') return list;
      if(c!=',') throw new JSONException("comma");
    }
  }
  private String string() throws JSONException {
    if(s.charAt(i)!='"') throw new JSONException("string");
    i++; StringBuilder out=new StringBuilder();
    while(i<s.length()){
      char c=s.charAt(i++);
      if(c=='"') return out.toString();
      if(c!='\\\\'){ out.append(c); continue; }
      char escape=s.charAt(i++);
      if(escape=='n') out.append('\\n');
      else if(escape=='t') out.append('\\t');
      else if(escape=='r') out.append('\\r');
      else if(escape=='b') out.append('\\b');
      else if(escape=='f') out.append('\\f');
      else if(escape=='u'){ out.append((char)Integer.parseInt(s.substring(i,i+4),16)); i+=4; }
      else out.append(escape);
    }
    throw new JSONException("unterminated");
  }
  private Object number() throws JSONException {
    int start=i;
    while(i<s.length()&&"+-.eE0123456789".indexOf(s.charAt(i))>=0) i++;
    String text=s.substring(start,i);
    if(text.isEmpty()) throw new JSONException("number");
    return text.contains(".")||text.contains("e")||text.contains("E")
        ? (Object)Double.valueOf(text) : (Object)Long.valueOf(text);
  }
}''',
"org/json/JSONObject.java": '''
package org.json; import java.util.*;
public class JSONObject {
  private final Map<String,Object> map;
  public JSONObject(){ map=new LinkedHashMap<>(); }
  public JSONObject(String text) throws JSONException {
    Object value=Parser.parse(text);
    if(!(value instanceof Map)) throw new JSONException("object expected");
    map=new LinkedHashMap<>();
    for(Map.Entry<?,?> entry:((Map<?,?>)value).entrySet()) map.put(String.valueOf(entry.getKey()),entry.getValue());
  }
  public JSONObject optJSONObject(String key){ Object v=map.get(key); return v instanceof Map? wrap((Map<?,?>)v):null; }
  public JSONArray optJSONArray(String key){ Object v=map.get(key); return v instanceof List? new JSONArray((List<?>)v):null; }
  public String optString(String key){ Object v=map.get(key); return v==null?"":String.valueOf(v); }
  public long optLong(String key,long fallback){ Object v=map.get(key); return v instanceof Number?((Number)v).longValue():fallback; }
  static JSONObject wrap(Map<?,?> value){
    JSONObject object=new JSONObject();
    for(Map.Entry<?,?> entry:value.entrySet()) object.map.put(String.valueOf(entry.getKey()),entry.getValue());
    return object;
  }
}''',
"org/json/JSONArray.java": '''
package org.json; import java.util.*;
public class JSONArray {
  private final List<Object> list;
  JSONArray(List<?> values){ list=new ArrayList<>(values); }
  public int length(){ return list.size(); }
  public Object opt(int index){ return index>=0&&index<list.size()?list.get(index):null; }
  public JSONObject optJSONObject(int index){ Object v=opt(index); return v instanceof Map? JSONObject.wrap((Map<?,?>)v):null; }
  public JSONArray optJSONArray(int index){ Object v=opt(index); return v instanceof List? new JSONArray((List<?>)v):null; }
  public String optString(int index){ Object v=opt(index); return v==null?"":String.valueOf(v); }
}''',
"xyz/i4o/uni/launcher/integration/LyricsResolverContractTest.java": '''
package xyz.i4o.uni.launcher.integration;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;

public final class LyricsResolverContractTest {
  private static int checks;
  private static void ok(boolean condition,String message){ checks++; if(!condition) throw new AssertionError(message); }

  private static final String NETEASE_SEARCH = """
      {"result":{"songs":[
        {"id":1,"name":"起风了","artists":[{"name":"张杰"}],"duration":200000},
        {"id":2,"name":"起风了","artists":[{"name":"冯沁苑(买辣椒也用券)"}],"duration":325868}]}}
      """;
  private static final String NETEASE_LYRIC = """
      {"lrc":{"lyric":"[00:00.00]这一路上走走停停\\n[00:03.00]顺着少年漂流的痕迹"}}
      """;
  private static final String QQ_SEARCH = """
      {"data":{"song":{"list":[
        {"songname":"起风了","singer":[{"name":"张杰"}],"interval":200,"songmid":"WRONG"},
        {"songname":"起风了","singer":[{"name":"买辣椒也用券"}],"interval":325,"songmid":"003aAYrm3GE0Ac"}]}}}
      """;
  private static final String QQ_LYRIC = """
      {"lyric":"[00&#58;00.00]这一路上走走停停\\n[00&#58;03.00]顺着&#46;少年"}
      """;
  private static final String KUGOU_SEARCH = """
      {"data":{"lists":[{"SongName":"起风了","SingerName":"买辣椒也用券","Duration":325,"FileHash":"FILEHASH"}]}}
      """;
  private static final String KUGOU_CANDIDATE = """
      {"candidates":[{"id":"12345","accesskey":"ACCESS"}]}
      """;

  public static void main(String[] args) throws Exception {
    // A packed "artist - title" metadata field is split, track numbers dropped,
    // bracketed version noise ignored.
    String[] split = LyricsResolver.cleanQuery("周杰伦 - 起风了 (Live) [FLAC]", "");
    ok("起风了".equals(split[0]),"packed field keeps the title: " + split[0]);
    ok("周杰伦".equals(split[1]),"packed field keeps the artist: " + split[1]);
    ok("起风了".equals(LyricsResolver.cleanQuery("12. 起风了","买辣椒也用券")[0]),"track number dropped");
    ok("起风了".equals(LyricsResolver.stripNoise("起风了【Live】")),"bracket noise removed");
    ok("起风了".equals(LyricsResolver.stripNoise("起风了 (伴奏)")),"version noise removed");

    ok("起风了|周杰伦|180".equals(LyricsResolver.key("起风了","周杰伦",180000)),"stable identity key");
    ok(LyricsResolver.key("起风了 (Live)","周杰伦",180000).equals(LyricsResolver.key("起风了","周杰伦",180000)),
        "noise does not change identity");
    ok(LyricsResolver.key("","周杰伦",180000).isEmpty(),"missing title has no identity");

    ok(LyricsResolver.score("起风了","买辣椒也用券","起风了","买辣椒也用券",325000,326000)>=2,"same recording matches");
    ok(LyricsResolver.score("起风了","买辣椒也用券","起风了 (Live)","买辣椒也用券",325000,325000)>=2,"noise suffix still matches");
    ok(LyricsResolver.score("起风了","买辣椒也用券","起风了","冯沁苑(买辣椒也用券)",325000,325868)>=2,"bracketed alias still matches");
    ok(LyricsResolver.score("起风了","买辣椒也用券","起风了","张杰",325000,325000)<2,"another singer rejected");
    ok(LyricsResolver.score("起风了","买辣椒也用券","起风了","买辣椒也用券",325000,200000)==0,"duration mismatch rejected");
    ok(LyricsResolver.score("晴天","周杰伦","起风了","买辣椒也用券",200000,325000)==0,"different title rejected");

    ok(LyricsResolver.pickNeteaseId(NETEASE_SEARCH,"起风了","买辣椒也用券",325000)==2,"netease picks the recording");
    ok(LyricsResolver.pickNeteaseId(NETEASE_SEARCH,"起风了","买辣椒也用券",900000)==-1,"netease duration filters all");
    ok(LyricsResolver.neteaseLyrics(NETEASE_LYRIC).startsWith("[00:00.00]"),"netease lrc extracted");
    ok(LyricsResolver.neteaseLyrics("{\\"nolyric\\":true}").isEmpty(),"netease without lrc stays empty");

    ok("003aAYrm3GE0Ac".equals(LyricsResolver.pickQqMid(QQ_SEARCH,"起风了","买辣椒也用券",325000)),"qq picks the recording");
    String qq = LyricsResolver.qqLyrics(QQ_LYRIC);
    ok(qq.startsWith("[00:00.00]"),"qq entities decoded: " + qq);
    ok(qq.contains("顺着.少年"),"qq numeric entities decoded");
    ok(LyricsResolver.qqLyrics("{}").isEmpty(),"qq without lyric stays empty");

    ok("FILEHASH".equals(LyricsResolver.pickKugouHash(KUGOU_SEARCH,"起风了","买辣椒也用券",325000)),"kugou picks the recording");
    ok("".equals(LyricsResolver.pickKugouHash(KUGOU_SEARCH,"起风了","买辣椒也用券",900000)),"kugou duration filters all");
    ok("12345\\u0000ACCESS".equals(LyricsResolver.pickKugouCandidate(KUGOU_CANDIDATE)),"kugou candidate carries access key");
    ok(LyricsResolver.pickKugouCandidate("{\\"candidates\\":[]}").isEmpty(),"kugou without candidate stays empty");
    String plain = "\\ufeff[00:00.00]line1\\n[00:03.00]line2";
    String encoded = Base64.getEncoder().encodeToString(plain.getBytes("UTF-8"));
    ok("[00:00.00]line1\\n[00:03.00]line2".equals(LyricsResolver.kugouLyrics("{\\"content\\":\\"" + encoded + "\\"}")),
        "kugou base64 and BOM handled");
    ok(LyricsResolver.kugouLyrics("{\\"content\\":\\"****\\"}").isEmpty(),"kugou malformed payload stays empty");

    Path dir = Files.createTempDirectory("uni-lyrics-cache");
    LyricsResolver resolver = new LyricsResolver(dir.toFile(), null);
    String key = LyricsResolver.key("起风了","买辣椒也用券",325000);
    ok(resolver.cached("起风了","买辣椒也用券",325000).isEmpty(),"nothing cached before resolution");
    String text = "[00:00.00]这一路上走走停停";
    resolver.store(key,text);
    ok(text.equals(resolver.load(key)),"disk round trip");
    File[] cached = dir.toFile().listFiles();
    ok(cached != null && cached.length == 1 && cached[0].length() > 0,"cache file written");
    String huge = "x".repeat(LyricsResolver.MAX_LYRICS + 1);
    resolver.store("huge",huge);
    ok(resolver.load("huge").isEmpty(),"oversize document refused by disk cache");
    ok(LyricsResolver.neteaseLyrics("{\\"lrc\\":{\\"lyric\\":\\"" + huge + "\\"}}").isEmpty(),"oversize document refused");

    // Empty metadata never reaches the network or the worker.
    resolver.request("","买辣椒也用券",0);
    ok(resolver.cached("","买辣椒也用券",0).isEmpty(),"missing title is not requested");

    System.out.println("PASS " + checks + " lyrics contract assertions; JVM doubles only; no device, no network");
  }
}''',
}

for name, body in files.items():
    path = stubs / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")

out = root / "classes"
out.mkdir(exist_ok=True)
source = Path(__file__).resolve().parents[3] / "app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/LyricsResolver.java"
subprocess.run([jdk("javac"), "-encoding", "UTF-8", "-d", str(out)]
               + [str(p) for p in stubs.rglob("*.java")] + [str(source)], check=True)
subprocess.run([jdk("java"), "-cp", str(out),
                "xyz.i4o.uni.launcher.integration.LyricsResolverContractTest"], check=True)

temporary.cleanup()

