# Domokoncept /brag-slim — audio bed + SFX synth (one mix) -> WAV
$ErrorActionPreference = 'Stop'
$OUT = 'C:\Users\barcz\Documents\Domokoncept\DomokonceptWebsite\brag-output\work\brag_audio.wav'

$cs = @'
using System;
using System.IO;
public static class BragAudio {
  const int SR = 44100;
  static double Smooth(double x){ if(x<0)x=0; if(x>1)x=1; return x*x*(3-2*x); }
  // ADSR-ish window: fade in over a, hold, fade out over r, within [t0,t1]
  static double Env(double t,double t0,double t1,double a,double r){
    if(t<t0||t>t1) return 0;
    double g=1.0;
    if(t<t0+a) g=Smooth((t-t0)/a);
    double rem=t1-t;
    if(rem<r) g=Math.Min(g,Smooth(rem/r));
    return g;
  }
  public static void Generate(string path){
    double dur=20.6; int N=(int)(dur*SR);
    double[] L=new double[N]; double[] R=new double[N];
    Random rnd=new Random(7);

    // ---- chord progression (warm, C major family), ending on Cmaj7 ----
    double[][] chords=new double[][]{
      new double[]{261.63,329.63,392.00,493.88}, // Cmaj7
      new double[]{220.00,261.63,329.63,392.00}, // Am7
      new double[]{174.61,220.00,261.63,329.63}, // Fmaj7
      new double[]{196.00,246.94,293.66,329.63}, // G6/sus
      new double[]{261.63,329.63,392.00,493.88}, // Cmaj7
      new double[]{220.00,261.63,329.63,392.00}, // Am7
      new double[]{174.61,220.00,261.63,329.63}, // Fmaj7
      new double[]{261.63,329.63,392.00,523.25}  // Cmaj7 (resolve)
    };
    double step=2.55; // seconds per chord (8*2.55 = 20.4)
    double[] pan=new double[]{-0.30,-0.10,0.10,0.30};

    // ---- pad: overlapping enveloped chords, sine + soft octave/fifth, slight detune ----
    for(int c=0;c<chords.Length;c++){
      double t0=c*step - 0.30; double t1=c*step+step + 0.30; // overlap for crossfade
      if(t0<0)t0=0;
      int s0=(int)(t0*SR), s1=(int)(Math.Min(t1,dur)*SR);
      for(int ni=0;ni<chords[c].Length;ni++){
        double f=chords[c][ni];
        double gL=0.5*(1-pan[ni]), gR=0.5*(1+pan[ni]);
        for(int s=s0;s<s1;s++){
          double t=(double)s/SR;
          double e=Env(t,t0+0.0,t1,0.55,0.55);
          if(e<=0) continue;
          double ph=2*Math.PI*t;
          double v = Math.Sin(ph*f)
                   + 0.9*Math.Sin(ph*f*1.003)      // detune warmth
                   + 0.45*Math.Sin(ph*2*f)          // octave
                   + 0.20*Math.Sin(ph*3*f);         // soft fifth-ish
          v *= 0.5;
          double a=e*0.085*v;
          L[s]+=a*gL; R[s]+=a*gR;
        }
      }
      // sub bass: root one octave down
      double fb=chords[c][0]*0.5;
      for(int s=s0;s<s1;s++){
        double t=(double)s/SR; double e=Env(t,t0,t1,0.5,0.6); if(e<=0)continue;
        double v=Math.Sin(2*Math.PI*fb*t)+0.3*Math.Sin(2*Math.PI*fb*2*t);
        double a=e*0.10*v; L[s]+=a*0.5; R[s]+=a*0.5;
      }
    }

    // ---- gentle pluck for movement: root+fifth at each chord start, soft, short decay ----
    for(int c=1;c<chords.Length;c++){
      double[] notes=new double[]{chords[c][0]*2, chords[c][2]*2};
      for(int k=0;k<notes.Length;k++){
        double tev=c*step + k*0.18;
        AddPluck(L,R,tev,notes[k],0.045);
      }
    }

    // ---- SFX (same space, soft under music) ----
    double[] bounds=new double[]{3.2,6.6,10.2,13.8,16.8};
    foreach(double b in bounds) AddWhoosh(L,R,b-0.25,0.07,rnd);
    AddImpact(L,R,3.35,0.11);                       // logo reveal
    // count-up ticks during stats (10.55 -> 11.75)
    for(double tt=10.55; tt<11.75; tt+=0.11) AddTick(L,R,tt,0.020);
    AddShimmer(L,R,17.85,523.25,0.040);             // outro resolve shimmer

    // ---- reverb send (cheap Schroeder) on a mono bus, added back with width ----
    double[] mono=new double[N];
    for(int s=0;s<N;s++) mono[s]=0.5*(L[s]+R[s]);
    double[] wet=Reverb(mono);
    for(int s=0;s<N;s++){
      int d=(int)(0.011*SR); int sr=s-d; double wr=(sr>=0)?wet[sr]:0;
      L[s]+=0.18*wet[s]; R[s]+=0.18*wr;
    }

    // ---- master: gentle fade in/out, soft limiter, normalize ----
    for(int s=0;s<N;s++){
      double t=(double)s/SR;
      double g=1.0;
      if(t<0.4) g=Smooth(t/0.4);
      if(t>20.25) g=Math.Min(g,Smooth((dur-t)/(dur-20.25)));
      L[s]*=g; R[s]*=g;
    }
    double peak=1e-9;
    for(int s=0;s<N;s++){ peak=Math.Max(peak,Math.Abs(L[s])); peak=Math.Max(peak,Math.Abs(R[s])); }
    double gain=0.95/peak;                       // linear normalize to -0.45 dBFS
    for(int s=0;s<N;s++){
      double l=L[s]*gain, r=R[s]*gain;
      if(l>0.96) l=0.96+0.04*Math.Tanh((l-0.96)/0.04); else if(l<-0.96) l=-0.96+0.04*Math.Tanh((l+0.96)/0.04);
      if(r>0.96) r=0.96+0.04*Math.Tanh((r-0.96)/0.04); else if(r<-0.96) r=-0.96+0.04*Math.Tanh((r+0.96)/0.04);
      L[s]=l; R[s]=r;
    }

    WriteWav(path,L,R);
  }

  static void AddPluck(double[] L,double[] R,double tev,double f,double amp){
    int s0=(int)(tev*SR); int len=(int)(0.5*SR);
    for(int i=0;i<len;i++){ int s=s0+i; if(s<0||s>=L.Length)break;
      double t=(double)i/SR; double env=Math.Exp(-t*7.0)*Smooth(t/0.006);
      double v=(Math.Sin(2*Math.PI*f*t)+0.3*Math.Sin(2*Math.PI*2*f*t))*env*amp;
      L[s]+=v*0.5; R[s]+=v*0.5;
    }
  }
  static void AddWhoosh(double[] L,double[] R,double tev,double amp,Random rnd){
    int s0=(int)(tev*SR); int len=(int)(0.7*SR); double lp=0;
    for(int i=0;i<len;i++){ int s=s0+i; if(s<0||s>=L.Length)break;
      double t=(double)i/SR; double n=rnd.NextDouble()*2-1;
      lp += 0.08*(n-lp); // one-pole lowpass -> airy noise
      double env=Env(t,0,0.7,0.30,0.35);
      double sweep=0.6+0.4*Smooth(t/0.5);
      double v=lp*env*amp*sweep;
      L[s]+=v; R[s]+=v;
    }
  }
  static void AddImpact(double[] L,double[] R,double tev,double amp){
    int s0=(int)(tev*SR); int len=(int)(0.4*SR);
    for(int i=0;i<len;i++){ int s=s0+i; if(s<0||s>=L.Length)break;
      double t=(double)i/SR; double env=Math.Exp(-t*10.0);
      double f=78*Math.Exp(-t*6.0)+48; // slight pitch drop
      double v=Math.Sin(2*Math.PI*f*t)*env*amp;
      L[s]+=v*0.5; R[s]+=v*0.5;
    }
  }
  static void AddTick(double[] L,double[] R,double tev,double amp){
    int s0=(int)(tev*SR); int len=(int)(0.08*SR);
    for(int i=0;i<len;i++){ int s=s0+i; if(s<0||s>=L.Length)break;
      double t=(double)i/SR; double env=Math.Exp(-t*60.0);
      double v=Math.Sin(2*Math.PI*1850*t)*env*amp;
      L[s]+=v*0.5; R[s]+=v*0.5;
    }
  }
  static void AddShimmer(double[] L,double[] R,double tev,double f,double amp){
    int s0=(int)(tev*SR); int len=(int)(2.6*SR);
    for(int i=0;i<len;i++){ int s=s0+i; if(s<0||s>=L.Length)break;
      double t=(double)i/SR; double env=Env(t,0,2.6,0.8,0.8);
      double v=(Math.Sin(2*Math.PI*f*t)+0.5*Math.Sin(2*Math.PI*f*2*t))*env*amp;
      L[s]+=v*0.5; R[s]+=v*0.5;
    }
  }

  static double[] Reverb(double[] x){
    int N=x.Length; double[] outb=new double[N];
    int[] combs=new int[]{1557,1617,1491,1422};
    double[] fb=new double[]{0.70,0.71,0.69,0.70};
    double[] acc=new double[N];
    for(int c=0;c<combs.Length;c++){
      int d=combs[c]; double g=fb[c]; double[] buf=new double[d]; int idx=0; double filt=0;
      for(int s=0;s<N;s++){
        double y=buf[idx];
        filt += 0.40*(y-filt);     // lowpass damping in feedback: prevents runaway buildup
        buf[idx]=x[s]+filt*g;
        idx++; if(idx>=d)idx=0;
        acc[s]+=y*0.25;
      }
    }
    // two allpass
    int[] aps=new int[]{225,556}; double ag=0.5;
    double[] cur=acc;
    for(int a=0;a<aps.Length;a++){
      int d=aps[a]; double[] buf=new double[d]; int idx=0; double[] nx=new double[N];
      for(int s=0;s<N;s++){
        double bufout=buf[idx];
        double inp=cur[s];
        double y=-ag*inp+bufout;
        buf[idx]=inp+ag*bufout;
        idx++; if(idx>=d)idx=0;
        nx[s]=y;
      }
      cur=nx;
    }
    for(int s=0;s<N;s++) outb[s]=cur[s];
    return outb;
  }

  static void WriteWav(string path,double[] L,double[] R){
    int N=L.Length;
    using(FileStream fs=new FileStream(path,FileMode.Create))
    using(BinaryWriter w=new BinaryWriter(fs)){
      int byteRate=SR*2*2; int dataLen=N*2*2;
      w.Write(new char[]{'R','I','F','F'}); w.Write(36+dataLen);
      w.Write(new char[]{'W','A','V','E'});
      w.Write(new char[]{'f','m','t',' '}); w.Write(16); w.Write((short)1);
      w.Write((short)2); w.Write(SR); w.Write(byteRate); w.Write((short)4); w.Write((short)16);
      w.Write(new char[]{'d','a','t','a'}); w.Write(dataLen);
      for(int s=0;s<N;s++){
        short l=(short)(Math.Max(-1,Math.Min(1,L[s]))*32767);
        short r=(short)(Math.Max(-1,Math.Min(1,R[s]))*32767);
        w.Write(l); w.Write(r);
      }
    }
  }
}
'@

Add-Type -TypeDefinition $cs -Language CSharp
[BragAudio]::Generate($OUT)
$fi=Get-Item $OUT
"WAV written: {0}  ({1:N2} MB)" -f $OUT, ($fi.Length/1MB)
