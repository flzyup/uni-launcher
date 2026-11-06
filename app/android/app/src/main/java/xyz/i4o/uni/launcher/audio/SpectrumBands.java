package xyz.i4o.uni.launcher.audio;

/** Android Visualizer FFT is interleaved signed real/imaginary bytes (DC and
 * Nyquist occupy bytes 0/1). Only normalized logarithmic band energies escape. */
public final class SpectrumBands {
    public static final int COUNT=24;
    /** Lowest band edge in hertz. */
    public static final double BOTTOM_HZ=60d;
    /** Highest band edge in hertz (the Nyquist half is used when it is lower). */
    public static final double TOP_HZ=14000d;
    /**
     * A raw sample rate above this is read as millihertz.
     *
     * <p>The head unit ROM reports {@code Visualizer.getSamplingRate()} in
     * millihertz (48000000), while a stock device reports hertz (44100).
     * Both are accepted, so the frequency axis is right on either.
     */
    public static final int MILLI_HZ_THRESHOLD=100000;
    /**
     * A sample rate below this is not a sample rate (it is 0, or the ROM
     * changed the unit).
     */
    public static final int MIN_PLAUSIBLE_SAMPLE_RATE=1000;
    /**
     * The sample rate to assume when none can be read.
     *
     * <p>The car runs at 48 kHz, so that is the fallback. Without a fallback a
     * rate of 0 makes every band decode to zero: the spectrum would be
     * silent forever and nothing would say why.
     */
    public static final int DEFAULT_SAMPLE_RATE=48000;
    private SpectrumBands(){}

    /**
     * Normalizes a raw sample rate to hertz.
     *
     * @param raw the value of {@code Visualizer.getSamplingRate()}
     * @return the rate in hertz, or 0 when the value is not usable
     */
    public static int normalizeSampleRate(int raw){
        if(raw<=0)return 0;
        return raw>=MILLI_HZ_THRESHOLD?raw/1000:raw;
    }

    /**
     * Whether a normalized sample rate can be used for the frequency axis.
     */
    public static boolean isPlausibleSampleRate(int sampleRate){
        return sampleRate>=MIN_PLAUSIBLE_SAMPLE_RATE;
    }

    /**
     * Decodes one FFT frame into the band energies.
     *
     * @param fft the raw bytes of {@code Visualizer.getFft()}
     * @param sampleRate the sample rate, in hertz or in millihertz (both are
     *   accepted, see {@link #normalizeSampleRate(int)})
     */
    public static double[] decode(byte[] fft,int sampleRate){
        double[] result=new double[COUNT];
        decodeInto(fft,sampleRate,result);
        return result;
    }

    /**
     * Decodes one FFT frame into {@code out} without allocating.
     *
     * <p>Same numbers as {@link #decode(byte[],int)}; the caller may hand in a
     * reused buffer, which is what the 20 Hz capture loop does. {@code out} is
     * zeroed first, so a failed frame reads as silence.
     */
    public static void decodeInto(byte[] fft,int sampleRate,double[] out){
        for(int i=0;i<COUNT&&i<out.length;i++)out[i]=0;
        if(fft==null||fft.length<8||out.length<COUNT)return;
        int hz=normalizeSampleRate(sampleRate);
        if(hz<=0)return;
        Plan plan=planFor(fft.length,hz);
        for(int band=0;band<COUNT;band++){
            double power=0;
            int last=plan.last[band];
            for(int k=plan.first[band];k<last;k++){
                double re=fft[k*2],im=fft[k*2+1];
                power=Math.max(power,re*re+im*im);
            }
            if(power>0){
                double db=10*Math.log10(power/(128d*128d*2));
                out[band]=Math.max(0,Math.min(1,(db+54)/54));
            }
        }
    }

    /**
     * Band edges for one (fft length, sample rate) pair.
     *
     * <p>Only those two inputs decide the bin ranges, and both are constant for
     * the life of a Visualizer handle — yet the per-frame path used to run two
     * {@code Math.pow} plus a floor and a ceil per band, 24 times, 20 times a
     * second, on the main thread. Caching the table removes that entirely.
     */
    private static final class Plan {
        final int fftLength,hz;
        final int[] first,last;
        Plan(int fftLength,int hz){
            this.fftLength=fftLength;this.hz=hz;
            int bins=fftLength/2;
            double top=Math.min(TOP_HZ,hz/2d),bottom=Math.min(BOTTOM_HZ,top/2);
            first=new int[COUNT];last=new int[COUNT];
            for(int band=0;band<COUNT;band++){
                double lo=bottom*Math.pow(top/bottom,band/(double)COUNT);
                double hi=bottom*Math.pow(top/bottom,(band+1d)/COUNT);
                first[band]=Math.max(1,Math.min(bins-1,(int)Math.floor(lo*fftLength/hz)));
                last[band]=Math.max(first[band]+1,Math.min(bins,(int)Math.ceil(hi*fftLength/hz)));
            }
        }
    }
    /** 只留最后一张表：切换播放会话时采样率会变，但只变一次。 */
    private static volatile Plan plan;
    private static Plan planFor(int fftLength,int hz){
        Plan current=plan;
        if(current!=null&&current.fftLength==fftLength&&current.hz==hz)return current;
        Plan next=new Plan(fftLength,hz);
        plan=next;
        return next;
    }
}
