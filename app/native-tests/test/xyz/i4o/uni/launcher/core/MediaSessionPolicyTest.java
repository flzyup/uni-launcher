package xyz.i4o.uni.launcher.core;
public final class MediaSessionPolicyTest {
  static void expect(boolean value,String label){if(!value)throw new AssertionError(label);}
  public static void main(String[] args){
    String[] names={"player","player","ecarx.xsf.mediacenter"};
    expect(MediaSourcePolicy.selectSessions("player","",names,new boolean[]{false,false,true},new boolean[]{false,true,true},new boolean[]{false,false,false})==1,"locked player chooses metadata-bearing session");
    expect(MediaSourcePolicy.selectSessions("auto","player",names,new boolean[]{false,false,true},new boolean[]{false,false,true},new boolean[]{false,true,false})==1,"paused session survives transient metadata loss");
    expect(MediaSourcePolicy.selectSessions("auto","player",new String[]{"player","other"},new boolean[]{false,true},new boolean[]{true,true},new boolean[]{true,false})==1,"new active player wins");
    expect(MediaSourcePolicy.selectSessions("missing","",names,new boolean[]{false,false,true},new boolean[]{false,true,true},new boolean[]{false,false,false})==-1,"explicit source does not fall back");
    expect(MediaSourcePolicy.selectSessions("auto","player",new String[]{"ecarx.xsf.mediacenter"},new boolean[]{false},new boolean[]{false},new boolean[]{false})==-1,"empty proxy cannot mask remembered source");
    expect(MediaSourcePolicy.selectSessions("auto","player",new String[]{"ecarx.xsf.mediacenter"},new boolean[]{true},new boolean[]{true},new boolean[]{false})==0,"real playing system source remains available");
    MediaTextRetention c=new MediaTextRetention();
    MediaTextRetention.Track t=new MediaTextRetention.Track("Song","Artist","Album",1000);
    expect(c.update("token-a",false,t).title.equals("Song"),"initial metadata");
    expect(c.update("token-a",true,null).title.equals("Song"),"paused metadata retained");
    expect(!c.update("token-a",false,null).known(),"playing without metadata is not presented as an old song");
    expect(!c.update("token-a",true,null).known(),"cleared metadata cannot reappear after a later pause");
    expect(!c.update("token-b",true,null).known(),"other session never inherits old metadata");
    expect(c.update("token-b",true,new MediaTextRetention.Track("New","","",0)).title.equals("New"),"new metadata replaces cache");
    c.clear();
    expect(!c.update("token-b",true,null).known(),"cache can be cleared");
    System.out.println("MediaSessionPolicyTest passed");
  }
}
