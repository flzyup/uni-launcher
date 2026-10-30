package xyz.i4o.uni.launcher.audio;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/**
 * The frequency axis of the spectrum.
 *
 * <p>These cases pin down the mapping from the FFT buffer to the 24 bands.
 * The mapping is easy to get wrong by a factor of a thousand, and such a bug
 * does not crash: the bands simply read a part of the spectrum nobody asked
 * for, and the ambient light looks frozen.
 *
 * <p>No device and no audio are needed: the FFT buffer is built by hand.
 */
public class SpectrumBandsTest {

    /** The head unit ROM reports the sample rate in millihertz. */
    private static final int MILLI_HZ=48000000;

    /** A stock device reports it in hertz. */
    private static final int HZ=44100;

    /**
     * Builds an FFT buffer with one complex bin at full amplitude.
     *
     * @param captureSize the buffer size, which is also the number of FFT
     *     points
     * @param bin the bin that carries the tone
     */
    private static byte[] tone(int captureSize,int bin){
        byte[] fft=new byte[captureSize];
        fft[bin*2]=127;
        fft[bin*2+1]=127;
        return fft;
    }

    @Test
    public void theSampleRateIsNormalizedToHertz(){
        assertEquals(48000,SpectrumBands.normalizeSampleRate(MILLI_HZ));
        assertEquals(44100,SpectrumBands.normalizeSampleRate(HZ));
        assertEquals(0,SpectrumBands.normalizeSampleRate(0));
        assertEquals(0,SpectrumBands.normalizeSampleRate(-1));
    }

    @Test
    public void theBandDependsOnTheFrequencyNotOnTheUnit(){
        // The same tone, read with either unit, has to land in the same band:
        // a band is a frequency range, not a bin number.
        int binAtMilliHz=1500*1024/48000;
        int binAtHertz=1500*1024/44100;
        assertEquals(14,loudest(SpectrumBands.decode(tone(1024,binAtMilliHz),MILLI_HZ)));
        assertEquals(14,loudest(SpectrumBands.decode(tone(1024,binAtHertz),HZ)));
    }

    @Test
    public void theFourLowBandsCollapseWith512Points(){
        // 512 points at 48 kHz give a bin width of 93.75 Hz, so the four
        // bands from 60 Hz to 149 Hz all read the very same bin and their
        // energies are always equal. That is what pinned the hue at 0
        // degrees (red) and the brightness at its maximum.
        double[] bands=SpectrumBands.decode(tone(512,1),MILLI_HZ);
        assertTrue("低频段要有能量",bands[0]>0.9);
        assertEquals("四段低频必须相等（塌进同一个 bin）",bands[0],bands[1],.001);
        assertEquals(bands[0],bands[2],.001);
        assertEquals(bands[0],bands[3],.001);
    }

    @Test
    public void theFourLowBandsSeparateWith1024Points(){
        // 1024 points give a bin width of 46.875 Hz, so the four bands read
        // different bins and the pitch can be told apart.
        double[] bands=SpectrumBands.decode(tone(1024,2),MILLI_HZ);
        assertEquals("最低那段读的是别的 bin",0d,bands[0],.001);
        assertTrue("第二段要读到能量",bands[1]>.9);
        assertTrue("第三段要读到能量",bands[2]>.9);
        assertTrue("第四段要读到能量",bands[3]>.9);
    }

    @Test
    public void aToneLandsInTheBandOfItsFrequency(){
        // Bin 32 of 1024 points at 48 kHz is 1500 Hz, which sits in the
        // band from about 1443 Hz to about 1814 Hz: band 14.
        double[] bands=SpectrumBands.decode(tone(1024,32),MILLI_HZ);
        assertEquals("1500Hz 落在第 14 段",14,loudest(bands));
        assertTrue("该段要有能量",bands[14]>.9);
    }

    @Test
    public void silenceDecodesToZero(){
        double[] bands=SpectrumBands.decode(new byte[1024],MILLI_HZ);
        for(double band:bands)assertEquals(0d,band,.001);
    }

    @Test
    public void anUnusableSampleRateDecodesToZero(){
        double[] bands=SpectrumBands.decode(tone(1024,32),0);
        for(double band:bands)assertEquals(0d,band,.001);
    }

    /** The index of the loudest band. */
    private static int loudest(double[] bands){
        int best=0;
        for(int i=1;i<bands.length;i++)if(bands[i]>bands[best])best=i;
        return best;
    }
}
