package xyz.i4o.uni.launcher.overlay;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Raw application flags, before PhoneWindowManager applies policy_control.
 * Never infer app intent from global nav visibility: UNI itself hides OEM bars.
 * Android 9 has no non-exclusive public observer for another window's flags.
 */
public final class ImmersiveWindowState {
    private static final Pattern WINDOW = Pattern.compile("(?m)^  Window #\\d+ Window\\{([^ }]+)[^\\n]*");
    private static final Pattern FLAGS = Pattern.compile("mSystemUiVisibility=0x([0-9a-fA-F]+)");
    private static final Pattern DISPLAY = Pattern.compile("mDisplayId=(\\d+)");
    private static final Pattern FOCUS = Pattern.compile("mCurrentFocus=Window\\{([^ }]+)");
    private static final long HIDE_NAVIGATION = 0x2;
    private static final long IMMERSIVE = 0x800;
    private static final long IMMERSIVE_STICKY = 0x1000;
    public final boolean known, immersive;
    private ImmersiveWindowState(boolean known, boolean immersive) {
        this.known=known;this.immersive=immersive;
    }
    public static ImmersiveWindowState unknown(){return new ImmersiveWindowState(false,false);}
    public static ImmersiveWindowState normal(){return new ImmersiveWindowState(true,false);}
    public static ImmersiveWindowState parse(String dump,String pkg) {
        if(dump==null||pkg==null||pkg.isEmpty())return unknown();
        Matcher focus=FOCUS.matcher(dump);String focused=focus.find()?focus.group(1):"";
        Matcher windows=WINDOW.matcher(dump);
        Boolean first=null;
        while(windows.find()) {
            String id=windows.group(1);int begin=windows.end();
            Matcher next=WINDOW.matcher(dump);boolean foundNext=next.find(begin);
            String block=dump.substring(begin,foundNext?next.start():dump.length());
            if(!block.contains("package="+pkg+" ")&&!block.contains("package="+pkg+"\n"))continue;
            Matcher display=DISPLAY.matcher(block);
            if(!display.find()||!"0".equals(display.group(1)))continue;
            if(!block.contains("mViewVisibility=0x0 ")||!block.contains("isOnScreen=true"))continue;
            Matcher flags=FLAGS.matcher(block);
            if(!flags.find())continue;
            // This is a custom strip, not the system navigation bar. Respect an
            // explicit immersive request even if HIDE_NAVIGATION is absent:
            // NetEase 6.2.81 uses 0x1500 and draws to the physical screen bottom.
            // Layout/fullscreen flags alone must not hide the strip, nor may
            // policy_control's globally forced immersive mode count as intent.
            boolean hide=(Long.parseLong(flags.group(1),16)
                    &(HIDE_NAVIGATION|IMMERSIVE|IMMERSIVE_STICKY))!=0;
            if(id.equals(focused))return new ImmersiveWindowState(true,hide);
            if(first==null)first=hide;
        }
        return first==null?unknown():new ImmersiveWindowState(true,first);
    }
}
