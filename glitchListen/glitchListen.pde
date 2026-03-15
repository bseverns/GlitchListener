/**
 * ─────────────────────────────────────────────────────────────────────────────
 * Glitch Geometry Listener (XL) — FULLY ANNOTATED TEACHING VERSION
 * ─────────────────────────────────────────────────────────────────────────────
 * PURPOSE
 *   • Listen to a live audio feed (mic/loopback) using Minim.
 *   • Analyze sound (RMS, FFT bands, spectral centroid, spectral flux, onset).
 *   • Spawn short-lived, layered “glitch forms” (complex geometries).
 *   • Post-process the whole frame with: RGB channel split, feedback smear, strobe.
 *   • Provide OSC in/out for rig control and telemetry.
 *   • Save/Load presets (JSON) so a “look” can be recalled during a show.
 *
 * PEDAGOGY
 *   • Split into clear sections with careful comments explaining each concept:
 *     - imports, globals, setup/draw, analysis, effects, spawner, OSC, presets, forms
 *
 * CONTROLS (keyboard)
 *   SPACE  = spawn a form now
 *   C      = toggle RGB channel split
 *   F      = toggle feedback pass
 *   G      = toggle grainy fade floor (the slow black fade)
 *   B      = toggle beat-linked strobe
 *   V      = cycle the active palette mood
 *   O      = toggle cinematic overlay framing
 *   [ / ]  = strobe intensity down/up
 *   - / =  = feedback amount down/up
 *   , / .  = feedback rotation down/up
 *   ; / '  = feedback zoom down/up
 *   P      = save a preset JSON to data/
 *   L      = load the most recent preset JSON from data/
 *   S      = saveFrame("glitch-####.png")
 *   I      = show/hide on-screen help box
 *
 * OSC (defaults): listen on 127.0.0.1:9000, send to 127.0.0.1:9001
 *   IN:
 *     /glitch/rgbShift        float 0..1 (0=off, 1=on)
 *     /glitch/strobe          float 0..1
 *     /glitch/strobeIntensity float 0..1
 *     /glitch/feedback        float 0..1
 *     /glitch/fbAmount        float 0..1
 *     /glitch/fbRotate        float -1..1  (mapped to small radians)
 *     /glitch/fbZoom          float 0.9..1.1
 *     /glitch/spawn           float >0 triggers one spawn
 *   OUT (each frame):
 *     /glitch/telemetry rms, flux, centroid, bass, mid, high, forms(int)
 */

// ── Imports ──────────────────────────────────────────────────────────────────
// Minim: audio input + FFT
import ddf.minim.*;
import ddf.minim.analysis.*;

// OSC: networking for remote control / telemetry
import oscP5.*;
import netP5.*;

// ── Audio Analysis Globals ───────────────────────────────────────────────────
Minim minim;            // audio engine
AudioInput in;          // mic/line input (mono is fine for analysis)
FFT fft;                // frequency transform
BeatDetect beat;        // onset detector (simple beat heuristic)

// Per-frame analysis results (we compute these each draw())
float rms, peak;            // loudness (root mean square), instantaneous peak
float spectralCentroid;     // “brightness” of spectrum (Hz-weighted average)
float spectralFlux;         // how much the spectrum changed since last frame
float[] lastSpectrum;       // previous FFT bins, used to compute flux

// “Bands” = simple low/mid/high buckets (smoothed for visual stability)
float smoothedBass = 0;
float smoothedMid  = 0;
float smoothedHigh = 0;

// ── Visual / State Globals ───────────────────────────────────────────────────
ArrayList<GlitchForm> forms = new ArrayList<GlitchForm>(); // active geometry
ArrayList<CloudParticle> clouds = new ArrayList<CloudParticle>(); // lingering dust
int maxForms = 16;                                         // cap the chaos (overkill but keeps every beat)

// Offscreen buffers for effects
PGraphics fb;          // framebuffer used for feedback smear
PGraphics frameCopy;   // copy of current frame for RGB channel split

// Effect toggles
boolean doRGBShift  = true;  // channel-split glitch
boolean doFeedback  = true;  // smear/zoom/rotate previous frame
boolean doFadeFloor = true;  // slow fading-to-black background
boolean showHelp    = true;  // on-screen command cheat sheet
boolean cinematicOverlay = true; // filmic framing + scanline treatment

PaletteMood[] moods;        // curated color worlds for more intentional looks
int paletteIndex = 0;       // active palette

// Global “camera shake” knob (derived from audio energy)
float globalShake = 0;

// ── Spawning Control (prevents absurd spawn rates) ───────────────────────────
int lastSpawnFrame = 0;       // when we spawned last
int minSpawnGapFrames = 10;   // frames to wait before next allowed spawn

// ── Strobe Effect Params ─────────────────────────────────────────────────────
boolean strobeOn          = true;  // master on/off
float   strobeIntensity   = 0.65;  // 0..1 alpha of white flash
boolean strobeBeatLinked  = true;  // flash on beat?
int     strobeHoldFrames  = 2;     // flash duration (frames)
int     strobeCountdown   = 0;     // internal counter for flash

// ── Feedback Effect Params ───────────────────────────────────────────────────
float fbAmount = 0.82;   // opacity of previous frame (0=none, 1=full)
float fbRotate = 0.005;  // radians of rotation per frame (tiny)
float fbZoom   = 1.004;  // >1 = slow zoom-in; <1 = zoom-out

// ── OSC Networking (change ports/addr if needed) ─────────────────────────────
OscP5 osc;                                         // OSC server (incoming)
NetAddress oscOut = new NetAddress("127.0.0.1", 9001); // where we send frames
int oscInPort = 9000;                              // where we listen

// ── Processing setup(): runs once at program start ───────────────────────────
void settings() {
  // JAVA2D is more stable than P2D/JOGL on this machine with these post passes.
  size(1000, 1000);
  smooth(4); // anti-aliasing
}

void setup() {
  surface.setTitle("Glitch Geometry Listener (XL) — Teaching Build");
  frameRate(60); // steady 60 fps target

  initPalettes();

  // Initialize Minim + audio input
  minim = new Minim(this);
  // getLineIn(mode, bufferSize, sampleRate, bitDepth)
  // MONO is fine for analysis; buffer 1024 balances latency/resolution
  in    = minim.getLineIn(Minim.MONO, 1024, 44100.0f, 16);

  // FFT configured to match buffer + sample rate
  fft   = new FFT(in.bufferSize(), in.sampleRate());
  // Create a set of logarithmically spaced averages (more detail in lows)
  fft.logAverages(22, 3);

  // Simple onset detector; sensitivity “locks out” new beats for N ms
  beat  = new BeatDetect(in.bufferSize(), (int)in.sampleRate());
  beat.setSensitivity(80); // try 50–120ms depending on your material

  // Store last frame’s spectrum to compute flux
  lastSpectrum = new float[fft.specSize()];

  // Offscreen buffers
  fb        = createGraphics(width, height);
  frameCopy = createGraphics(width, height);

  // Start OSC server
  osc = new OscP5(this, oscInPort);

  // Initial clear
  resetSceneWash();
}

// ── Processing draw(): runs every frame ───────────────────────────────────────
void draw() {
  // 1) Audio analysis first: updates rms, bands, centroid, flux, beat state
  analyzeAudio();

  // 2) Spawning logic (may create a new geometry form on bursts)
  maybeSpawn();

  // 3) Repaint the stage with translucent palette washes and cinematic light
  paintAtmosphere();

  // 4) Update lingering dust clouds that give the scene a hazy floor
  for (int i = clouds.size()-1; i >= 0; i--) {
    CloudParticle p = clouds.get(i);
    p.update();
    p.draw();
    if (p.dead()) clouds.remove(i);
  }

  // 5) “Camera shake” for energy — subtle random motion based on analysis
  float energy = constrain(rms * 5 + smoothedHigh * 0.7 + (beat.isOnset() ? 0.4 : 0), 0, 2);
  globalShake  = lerp(globalShake, energy * 12, 0.1);

  // Apply camera shake & tiny rotation to the whole scene while drawing forms
  pushMatrix();
  translate(width/2f, height/2f); // draw forms around center
  translate(random(-globalShake, globalShake), random(-globalShake, globalShake));
  rotate(radians(random(-0.2, 0.2)));

  // 6) Draw/update forms; remove dead ones (short lifespans → restless look)
  for (int i = forms.size()-1; i >= 0; i--) {
    GlitchForm f = forms.get(i);
    f.update(rms, smoothedBass, smoothedMid, smoothedHigh, spectralCentroid, beat.isOnset());
    f.draw();    // each form has its own geometry logic
    if (f.dead()) forms.remove(i);
  }
  popMatrix();

  // 7) Post passes: RGB split (channel offsets), then Feedback smear, then Strobe
  if (doRGBShift) rgbSplitComposite();
  if (doFeedback) applyFeedback();
  if (strobeOn)   strobePass();
  if (cinematicOverlay) drawCinematicOverlay();

  // 8) Optional on-screen command crib sheet
  if (showHelp) drawHelp();

  // 9) Send telemetry each frame for your rig / recording
  sendTelemetry();
}

// ── Cleanup (called by Processing on stop) ───────────────────────────────────
void stop() {
  in.close();
  minim.stop();
  super.stop();
}

// ── LOOK SYSTEM: palettes + atmospheric stage painting ──────────────────────
void initPalettes() {
  moods = new PaletteMood[] {
    new PaletteMood(
      "Sunset Siren",
      color(6, 10, 22),
      color(17, 54, 84),
      color(255, 120, 84),
      color(70, 154, 255),
      color(255, 176, 92),
      color(255, 243, 199),
      color(9, 5, 12)
    ),
    new PaletteMood(
      "Petrol Bloom",
      color(4, 18, 18),
      color(14, 74, 72),
      color(255, 145, 92),
      color(72, 219, 182),
      color(221, 245, 110),
      color(255, 236, 196),
      color(4, 10, 8)
    ),
    new PaletteMood(
      "Rust Signal",
      color(20, 7, 10),
      color(84, 30, 20),
      color(255, 104, 72),
      color(74, 202, 215),
      color(232, 142, 56),
      color(255, 231, 202),
      color(10, 4, 4)
    )
  };
}

PaletteMood currentMood() {
  return moods[paletteIndex];
}

int withAlpha(int c, float a) {
  return color(red(c), green(c), blue(c), constrain(a, 0, 255));
}

void cyclePalette() {
  paletteIndex = (paletteIndex + 1) % moods.length;
  resetSceneWash();
}

void resetSceneWash() {
  PaletteMood mood = currentMood();
  background(mood.bgDark);
  fb.beginDraw();
  fb.background(mood.bgDark);
  fb.endDraw();
}

void paintAtmosphere() {
  PaletteMood mood = currentMood();
  blendMode(BLEND);
  noStroke();

  float washAlpha = doFadeFloor ? 42 : 16;
  fill(withAlpha(mood.bgDark, washAlpha));
  rect(0, 0, width, height);

  for (int y = 0; y < height; y += 18) {
    float amt = pow(y / (float)height, 0.8);
    int bandCol = lerpColor(mood.bgMid, mood.bgDark, amt);
    fill(withAlpha(bandCol, doFadeFloor ? 26 : 10));
    rect(0, y, width, 22);
  }

  float bassGlow = map(smoothedBass, 0, 0.5, 160, 620);
  float midGlow  = map(smoothedMid,  0, 0.45, 100, 380);
  float highGlow = map(smoothedHigh, 0, 0.35, 80, 240);

  fill(withAlpha(mood.glow, 18 + smoothedBass * 120));
  ellipse(width * 0.5, height * 0.72, bassGlow * 2.0, bassGlow * 0.9);

  fill(withAlpha(mood.accentLow, 14 + smoothedMid * 90));
  ellipse(width * 0.22, height * 0.28, midGlow * 1.9, midGlow * 1.2);

  fill(withAlpha(mood.accentMid, 12 + smoothedHigh * 140));
  ellipse(width * 0.78, height * 0.24, highGlow * 2.2, highGlow * 1.6);

  for (int i = 0; i < 6; i++) {
    float drift = frameCount * 0.004f + i * 9.7f;
    float px = width * (0.1f + 0.8f * noise(20 + i * 0.31f, drift));
    float py = height * (0.2f + 0.55f * noise(80 + i * 0.27f, drift));
    float pw = 90 + 180 * noise(140 + i * 0.19f, drift);
    float ph = 180 + 280 * noise(220 + i * 0.22f, drift);
    int plumeCol = lerpColor(mood.accentLow, mood.accentHigh, i / 5.0f);
    fill(withAlpha(plumeCol, 8 + spectralFlux * 600));
    ellipse(px, py, pw, ph);
  }

  noFill();
  stroke(withAlpha(mood.accentHigh, 18 + peak * 180));
  strokeWeight(1.2);
  ellipse(width * 0.5, height * 0.5, 300 + bassGlow * 0.35, 300 + bassGlow * 0.35);
  stroke(withAlpha(mood.accentMid, 12 + smoothedHigh * 130));
  ellipse(width * 0.5, height * 0.5, 540 + midGlow * 0.25, 540 + midGlow * 0.16);
}

void drawCinematicOverlay() {
  PaletteMood mood = currentMood();
  pushStyle();
  blendMode(BLEND);

  strokeWeight(1);
  for (int y = 0; y < height; y += 4) {
    stroke(withAlpha(mood.accentHigh, 5));
    line(0, y, width, y);
  }

  noFill();
  for (int i = 0; i < 9; i++) {
    float inset = i * 10;
    stroke(withAlpha(mood.ink, 18 + i * 3));
    strokeWeight(10);
    rect(inset, inset, width - inset * 2, height - inset * 2, 24);
  }

  strokeWeight(1.3);
  stroke(withAlpha(mood.glow, 45));
  rect(18, 18, width - 36, height - 36, 24);

  float arm = 72;
  stroke(withAlpha(mood.accentMid, 55));
  line(30, 30, 30 + arm, 30);
  line(30, 30, 30, 30 + arm);
  line(width - 30, 30, width - 30 - arm, 30);
  line(width - 30, 30, width - 30, 30 + arm);
  line(30, height - 30, 30 + arm, height - 30);
  line(30, height - 30, 30, height - 30 - arm);
  line(width - 30, height - 30, width - 30 - arm, height - 30);
  line(width - 30, height - 30, width - 30, height - 30 - arm);
  popStyle();
}

// ── AUDIO ANALYSIS: compute RMS, bands, centroid, flux, and detect onsets ───
void analyzeAudio() {
  // Compute RMS (root mean square) and peak for this audio buffer.
  // Concept: RMS ~ perceived loudness. Peak ~ instantaneous max.
  float sumSq = 0;
  peak = 0;
  for (int i = 0; i < in.bufferSize(); i++) {
    float v = in.mix.get(i);
    sumSq += v * v;
    peak = max(peak, abs(v));
  }
  rms = sqrt(sumSq / in.bufferSize());

  // FFT: from time domain (samples) → frequency domain (bins).
  // We use a window function to reduce spectral leakage.
  fft.window(FFT.HAMMING);
  fft.forward(in.mix);

  // Simple band aggregation:
  // low  ( < 200Hz ) for bass/rumble
  // mid  (200–2000Hz) for body/snarls
  // high ( > 2kHz )  for hiss/brightness
  float bass = 0, mid = 0, high = 0;
  int n = fft.specSize();
  for (int i = 0; i < n; i++) {
    float freq = i * (in.sampleRate()/2.0) / n;   // map bin index → Hz
    float mag  = fft.getBand(i);
    if (freq < 200)         bass += mag;
    else if (freq < 2000)   mid  += mag;
    else                    high += mag;
  }
  // Normalize roughly by bin count to keep values in a friendly range
  float norm = 1.0 / max(1, n);
  bass *= norm; mid *= norm; high *= norm;

  // Smooth the bands so visuals don’t jitter frame-to-frame
  smoothedBass = lerp(smoothedBass, bass, 0.15);
  smoothedMid  = lerp(smoothedMid,  mid,  0.15);
  smoothedHigh = lerp(smoothedHigh, high, 0.15);

  // Spectral Centroid: weighted average of frequency by magnitude.
  // Intuition: if energy shifts to higher frequencies, centroid rises.
  float num = 0, den = 0;
  for (int i = 0; i < n; i++) {
    float freq = i * (in.sampleRate()/2.0) / n;
    float mag  = fft.getBand(i) + 1e-9; // avoid divide-by-zero
    num += freq * mag;
    den += mag;
  }
  spectralCentroid = (den > 0) ? num / den : 0;

  // Spectral Flux: “how much did the spectrum change since last frame?”
  // Only positive changes contribute (common definition).
  float flux = 0;
  for (int i = 0; i < n; i++) {
    float cur  = fft.getBand(i);
    float diff = cur - lastSpectrum[i];
    if (diff > 0) flux += diff;
    lastSpectrum[i] = cur; // keep for next frame
  }
  spectralFlux = flux * norm;

  // Onset detection (beat-ish)
  beat.detect(in.mix);
}

// ── SPAWNING: create new geometry instances when the sound “bursts” ─────────
void maybeSpawn() {
  // Use FFT band energy: if any bucket punches hard, pop a form.
  boolean bassHit = smoothedBass > 0.3;
  boolean midHit  = smoothedMid  > 0.25;
  boolean highHit = smoothedHigh > 0.2;

  int band = -1; // 0=bass,1=mid,2=high
  if (bassHit && smoothedBass >= max(smoothedMid, smoothedHigh)) band = 0;
  else if (midHit && smoothedMid >= smoothedHigh)               band = 1;
  else if (highHit)                                             band = 2;

  // Rate-limit spawns so we don’t overwhelm the frame every single tick.
  if (band >= 0 && frameCount - lastSpawnFrame > minSpawnGapFrames) {
    spawnForm(band);
    lastSpawnFrame = frameCount;
  }

  // Enforce the active-form limit (remove oldest if over cap)
  while (forms.size() > maxForms) forms.remove(0);
}

// Default random spawn used by manual triggers/OSC
void spawnForm() { spawnForm(-1); }

// Spawn a form tuned to the frequency band that begged for attention
void spawnForm(int band) {
  GlitchForm f;
  switch (band) {
    case 0: // Bass: big chunky shapes
      f = random(1) < 0.5 ? new PolygonBurst() : new TriStripWeave();
      break;
    case 1: // Midrange: rounders and splines
      f = random(1) < 0.5 ? new NoisyDonut() : new SpiroSpline();
      break;
    case 2: // Highs: wiry scribbles
      f = new WireLissajous();
      break;
    default: // Fall back to full random chaos
      int choice = (int)random(5);
      switch (choice) {
        case 0: f = new PolygonBurst();  break;
        case 1: f = new WireLissajous(); break;
        case 2: f = new NoisyDonut();    break;
        case 3: f = new TriStripWeave(); break;
        default:f = new SpiroSpline();   break;
      }
      break;
  }
  forms.add(f);
}

// Spawn a puff of particles proportional to a form's complexity
void explode(GlitchForm f) {
  int count = min(200, f.complexity());
  float sx = width/2f + f.x;
  float sy = height/2f + f.y;
  for (int i = 0; i < count; i++) {
    clouds.add(new CloudParticle(sx, sy));
  }
  // keep clouds from growing without bound
  while (clouds.size() > 3000) clouds.remove(0);
}

// Single drifting dust mote used to build up persistent ground clouds
class CloudParticle {
  float x, y;
  float vx, vy;
  float life = 0;
  float lifeMax = random(400, 900);

  CloudParticle(float x, float y) {
    this.x = x;
    this.y = y;
    float ang = random(TWO_PI);
    float spd = random(0.5, 3);
    vx = cos(ang) * spd;
    vy = sin(ang) * spd;
  }

  void update() {
    x += vx;
    y += vy;
    vx *= 0.96;
    vy *= 0.96;
    life++;
  }

  boolean dead() { return life > lifeMax; }

  void draw() {
    noStroke();
    float a = map(life, 0, lifeMax, 60, 0);
    PaletteMood mood = currentMood();
    int dustCol = lerpColor(mood.accentLow, mood.accentHigh, noise(x * 0.002f, y * 0.002f));
    fill(withAlpha(dustCol, a));
    ellipse(x, y, 2.6, 2.6);
    fill(withAlpha(mood.glow, a * 0.35));
    ellipse(x, y, 7, 7);
  }
}

// ── EFFECT PASS: RGB channel split (chromatic aberration / glitch) ──────────
void rgbSplitComposite() {
  // 1) Copy the current frame into an offscreen buffer.
  // Avoid get() here: full-frame OpenGL readbacks can stall the animator.
  frameCopy.beginDraw();
  frameCopy.copy(g, 0, 0, width, height, 0, 0, width, height);
  frameCopy.endDraw();

  // 2) Compute how far to split channels. More highs + onsets → larger split
  float amt = map(smoothedHigh, 0, 0.6, 0, 12) + (beat.isOnset() ? 8 : 0);
  amt = constrain(amt, 0, 24);

  blendMode(BLEND);
  noTint();
  image(frameCopy, 0, 0);

  // 3) Add offset color ghosts without erasing the palette underneath.
  blendMode(SCREEN);
  tint(255, 90, 70, 105);   image(frameCopy,  amt,    0);      // warm right drift
  tint(90, 255, 180, 90);   image(frameCopy, -amt/2,  amt/3);  // green-cyan diagonal
  tint(90, 130, 255, 95);   image(frameCopy, -amt,   -amt/4);  // cool blue echo
  noTint();
  blendMode(BLEND);
}

// ── EFFECT PASS: Framebuffer feedback (smear/zoom/rotate previous frame) ────
void applyFeedback() {
  // Idea: re-draw a transformed version of the last frame on top of this one,
  // with some transparency. Over time, this creates a greasy echo of motion.
  fb.beginDraw();
  fb.blendMode(BLEND);
  fb.noStroke();

  // Transform around center so rotation/zoom feel “camera-like”
  fb.pushMatrix();
  fb.translate(fb.width/2f, fb.height/2f);
  fb.scale(fbZoom);     // slow zoom in/out
  fb.rotate(fbRotate);  // slight rotation each frame
  fb.translate(-fb.width/2f, -fb.height/2f);

  // Draw the *current* visible frame into fb with some alpha (fbAmount).
  // copy(g, ...) avoids the P2D readback path that get() uses.
  fb.tint(255, 255 * fbAmount);
  fb.copy(g, 0, 0, width, height, 0, 0, width, height);
  fb.noTint();

  fb.popMatrix();
  fb.endDraw();

  // Now blend the updated fb back onto the window (ADD brightens trails)
  blendMode(ADD);
  image(fb, 0, 0);
  blendMode(BLEND);
}

// ── EFFECT PASS: Strobe (full-frame white flash) ─────────────────────────────
void strobePass() {
  // Two ways to “fire” a flash:
  //  1) beat-linked (whenever beat.isOnset() is true)
  //  2) timed hold via strobeCountdown (for short flickers)
  boolean fire = false;
  if (strobeBeatLinked && beat.isOnset()) fire = true;
  if (strobeCountdown > 0) { fire = true; strobeCountdown--; }

  if (fire) {
    noStroke();
    float a = 255 * constrain(strobeIntensity, 0, 1);
    fill(255, a);
    rect(0, 0, width, height);
  }
}

// ── On-screen instructions ───────────────────────────────────────────────────
void drawHelp() {
  PaletteMood mood = currentMood();
  int w = 300, h = 292;
  int x = width - w - 24;
  int y = height - h - 24;
  pushStyle();
  fill(withAlpha(mood.ink, 215));
  noStroke();
  rect(x, y, w, h, 18);
  stroke(withAlpha(mood.glow, 80));
  strokeWeight(1.2);
  noFill();
  rect(x + 6, y + 6, w - 12, h - 12, 14);
  fill(mood.accentHigh);
  textAlign(LEFT, TOP);
  textSize(14);
  text("GLITCH LISTENER // " + mood.name, x + 18, y + 16);
  fill(withAlpha(mood.accentMid, 220));
  textSize(11);
  text("V: cycle palette", x + 18, y + 40);

  fill(255);
  textSize(12);
  String[] lines = {
    "SPACE: spawn",
    "C: RGB split",
    "F: feedback",
    "G: fade floor",
    "B: strobe",
    "V: palette",
    "O: overlay",
    "[ / ]: strobe lvl",
    "- / =: fb amount",
    ", / .: fb rotate",
    "; / ': fb zoom",
    "P: save preset",
    "L: load preset",
    "S: save frame",
    "I: hide help"
  };
  float ty = y + 68;
  for (String s : lines) {
    text(s, x + 18, ty);
    ty += 14;
  }

  fill(withAlpha(mood.accentLow, 220));
  text(
    "rms " + nf(rms, 1, 3) +
    "   flux " + nf(spectralFlux, 1, 3) +
    "   forms " + forms.size(),
    x + 18, y + h - 32
  );
  popStyle();
}

// ── OSC: receive control messages from other apps/devices ───────────────────
void oscEvent(OscMessage m) {
  String addr = m.addrPattern();

  if      (addr.equals("/glitch/rgbShift"))        doRGBShift = m.get(0).floatValue() > 0.5;
  else if (addr.equals("/glitch/strobe"))          strobeOn   = m.get(0).floatValue() > 0.5;
  else if (addr.equals("/glitch/strobeIntensity")) strobeIntensity = constrain(m.get(0).floatValue(), 0, 1);
  else if (addr.equals("/glitch/feedback"))        doFeedback = m.get(0).floatValue() > 0.5;
  else if (addr.equals("/glitch/fbAmount"))        fbAmount   = constrain(m.get(0).floatValue(), 0, 1);
  else if (addr.equals("/glitch/fbRotate"))        fbRotate   = m.get(0).floatValue() * 0.05; // scale small
  else if (addr.equals("/glitch/fbZoom"))          fbZoom     = constrain(m.get(0).floatValue(), 0.9, 1.1);
  else if (addr.equals("/glitch/spawn")) {
    if (m.get(0).floatValue() > 0) spawnForm();
  }
}

// Send one OSC packet per frame with analysis values (for metering/recording)
void sendTelemetry() {
  OscMessage out = new OscMessage("/glitch/telemetry");
  out.add(rms);
  out.add(spectralFlux);
  out.add(spectralCentroid);
  out.add(smoothedBass);
  out.add(smoothedMid);
  out.add(smoothedHigh);
  out.add(forms.size());
  osc.send(out, oscOut);
}

// ── PRESETS: Save current settings to JSON, load the most recent one ────────
void savePreset() {
  JSONObject j = new JSONObject();
  j.setBoolean("doRGBShift", doRGBShift);
  j.setBoolean("doFeedback", doFeedback);
  j.setBoolean("doFadeFloor", doFadeFloor);
  j.setBoolean("cinematicOverlay", cinematicOverlay);
  j.setBoolean("strobeOn", strobeOn);
  j.setBoolean("strobeBeatLinked", strobeBeatLinked);
  j.setFloat("strobeIntensity", strobeIntensity);
  j.setFloat("fbAmount", fbAmount);
  j.setFloat("fbRotate", fbRotate);
  j.setFloat("fbZoom", fbZoom);
  j.setInt("minSpawnGapFrames", minSpawnGapFrames);
  j.setInt("maxForms", maxForms);
  j.setInt("paletteIndex", paletteIndex);

  String fname = "preset_" + year()
               + nf(month(),2) + nf(day(),2) + "_"
               + nf(hour(),2) + nf(minute(),2) + nf(second(),2)
               + ".json";
  saveJSONObject(j, "data/" + fname);
  println("Saved preset: data/" + fname);
}

void loadMostRecentPreset() {
  java.io.File dataDir = new java.io.File(dataPath(""));
  if (!dataDir.exists()) { println("No data/ directory yet."); return; }
  java.io.File[] files = dataDir.listFiles();
  String best = null;
  for (java.io.File f : files) {
    if (f.getName().toLowerCase().endsWith(".json")) {
      if (best == null || f.getName().compareTo(best) > 0) best = f.getName();
    }
  }
  if (best == null) { println("No preset JSON found in data/."); return; }
  JSONObject j = loadJSONObject("data/" + best);

  doRGBShift        = j.getBoolean("doRGBShift", doRGBShift);
  doFeedback        = j.getBoolean("doFeedback", doFeedback);
  doFadeFloor       = j.getBoolean("doFadeFloor", doFadeFloor);
  cinematicOverlay  = j.getBoolean("cinematicOverlay", cinematicOverlay);
  strobeOn          = j.getBoolean("strobeOn", strobeOn);
  strobeBeatLinked  = j.getBoolean("strobeBeatLinked", strobeBeatLinked);
  strobeIntensity   = j.getFloat("strobeIntensity", strobeIntensity);
  fbAmount          = j.getFloat("fbAmount", fbAmount);
  fbRotate          = j.getFloat("fbRotate", fbRotate);
  fbZoom            = j.getFloat("fbZoom", fbZoom);
  minSpawnGapFrames = j.getInt("minSpawnGapFrames", minSpawnGapFrames);
  maxForms          = j.getInt("maxForms", maxForms);
  paletteIndex      = constrain(j.getInt("paletteIndex", paletteIndex), 0, moods.length - 1);

  resetSceneWash();
  println("Loaded preset: data/" + best);
}

class PaletteMood {
  String name;
  int bgDark, bgMid, glow, accentLow, accentMid, accentHigh, ink;

  PaletteMood(String name, int bgDark, int bgMid, int glow,
              int accentLow, int accentMid, int accentHigh, int ink) {
    this.name = name;
    this.bgDark = bgDark;
    this.bgMid = bgMid;
    this.glow = glow;
    this.accentLow = accentLow;
    this.accentMid = accentMid;
    this.accentHigh = accentHigh;
    this.ink = ink;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GEOMETRY SYSTEM: “GlitchForm” base class and five concrete forms
//   • Short-lived, jittery. Update with audio features, then draw.
//   • Each form chooses parameters at birth (seed/sides/etc.) to stay diverse.
// ─────────────────────────────────────────────────────────────────────────────

abstract class GlitchForm {
  // Birth timing + randomized life span for instability
  float born   = millis();
  float lifeMs = random(400, 1700);

  // Start somewhere around the screen with a bit of initial drift
  float x = 0;
  float y = 0;
  float vx = 0;
  float vy = 0;
  boolean exploded = false;
  float homeX = 0;
  float homeY = 0;
  float swirl = random(-0.04, 0.04);
  float driftStrength = random(0.55, 1.35);
  float settleStrength = random(0.0012, 0.0042);
  float noiseOffsetX = random(1000);
  float noiseOffsetY = random(1000);
  int motionMode = (int)random(4);

  // Rotation & spin
  float rot    = random(TWO_PI);
  float rotVel = random(-0.02, 0.02);

  // Random base scale (can be used by subclasses if desired)
  float scale0 = random(0.6, 1.4);

  // Random seed for per-instance coherency (noise/random patterns)
  int seed = (int)random(1<<24);

  // Visual styling
  int strokeCol = color(255);
  int fillCol   = color(255, 20);
  int haloCol   = color(255, 40);
  boolean additive = random(1) < 0.6; // choose ADD vs SCREEN blending

  GlitchForm() {
    // Mix interior launches, edge sweeps, and long diagonals for more varied staging.
    float rx = width * 0.42f;
    float ry = height * 0.42f;
    homeX = random(-width * 0.34f, width * 0.34f);
    homeY = random(-height * 0.34f, height * 0.34f);

    switch (motionMode) {
      case 0:
        x = random(-rx, rx);
        y = random(-ry, ry);
        vx = random(-2.5f, 2.5f);
        vy = random(-2.5f, 2.5f);
        break;
      case 1:
        if (random(1) < 0.5) {
          x = random(1) < 0.5 ? -width * 0.55f : width * 0.55f;
          y = random(-height * 0.3f, height * 0.3f);
        } else {
          x = random(-width * 0.3f, width * 0.3f);
          y = random(1) < 0.5 ? -height * 0.55f : height * 0.55f;
        }
        vx = (homeX - x) * 0.018f + random(-1.8f, 1.8f);
        vy = (homeY - y) * 0.018f + random(-1.8f, 1.8f);
        break;
      case 2:
        x = random(1) < 0.5 ? random(-width * 0.52f, -width * 0.18f) : random(width * 0.18f, width * 0.52f);
        y = random(1) < 0.5 ? -height * 0.52f : height * 0.52f;
        vx = random(-0.9f, 0.9f) + (homeX - x) * 0.01f;
        vy = random(-0.9f, 0.9f) + (homeY - y) * 0.01f;
        break;
      default:
        x = random(-width * 0.15f, width * 0.15f);
        y = random(-height * 0.15f, height * 0.15f);
        homeX = random(1) < 0.5 ? random(-width * 0.48f, -width * 0.18f) : random(width * 0.18f, width * 0.48f);
        homeY = random(1) < 0.5 ? random(-height * 0.48f, -height * 0.18f) : random(height * 0.18f, height * 0.48f);
        vx = random(-1.2f, 1.2f);
        vy = random(-1.2f, 1.2f);
        break;
    }
  }

  // Called each frame with fresh audio features
  void update(float rms, float bass, float mid, float high, float centroid, boolean onset) {
    // Spin a little, snap more on onsets
    rot += rotVel + (onset ? random(-0.1, 0.1) : 0);

    // Each form gets its own curved drift toward an off-center "home" point.
    float driftT = frameCount * 0.010f + seed * 0.00002f;
    float flowX = map(noise(noiseOffsetX, driftT), 0, 1, -1, 1);
    float flowY = map(noise(noiseOffsetY, driftT), 0, 1, -1, 1);
    vx += flowX * (0.7 + high * 2.6) * driftStrength;
    vy += flowY * (0.7 + mid  * 2.2) * driftStrength;

    float dx = homeX - x;
    float dy = homeY - y;
    float dist = max(40, sqrt(dx*dx + dy*dy));
    float pull = settleStrength * (0.65 + bass * 2.0);
    float curve = swirl * (0.8 + high * 1.4) / dist;
    vx += dx * pull - dy * curve;
    vy += dy * pull + dx * curve;

    if (onset) {
      vx += dx * 0.0025f + random(-1.4f, 1.4f);
      vy += dy * 0.0025f + random(-1.4f, 1.4f);
    }

    // Gravitational pull toward nearest edge ramps up as life expires
    float t = normLife();
    float grav = t*t*t * 0.8;
    float distLeft   = width/2f + x;
    float distRight  = width/2f - x;
    float distTop    = height/2f + y;
    float distBottom = height/2f - y;
    if (distLeft < distRight && distLeft < distTop && distLeft < distBottom)      vx -= grav;
    else if (distRight < distTop && distRight < distBottom)                       vx += grav;
    else if (distTop < distBottom)                                                vy -= grav;
    else                                                                          vy += grav;

    // Damp velocity and apply
    vx *= 0.98;
    vy *= 0.98;
    x  += vx;
    y  += vy;

    // Palette-driven color mapping feels more authored than raw RGB buckets.
    PaletteMood mood = currentMood();
    float bassAmt = constrain(bass * 3.0, 0, 1);
    float midAmt  = constrain(mid  * 3.0, 0, 1);
    float highAmt = constrain(high * 3.5, 0, 1);
    float total = max(0.001, bassAmt + midAmt + highAmt);

    int mixCol = lerpColor(mood.accentLow, mood.accentMid, midAmt / total);
    mixCol = lerpColor(mixCol, mood.accentHigh, highAmt / total);
    float brightMix = constrain(map(centroid, 250, 5000, 0.08, 0.92), 0, 1);
    strokeCol = lerpColor(mixCol, mood.glow, brightMix * 0.35 + (onset ? 0.18 : 0));
    fillCol   = withAlpha(lerpColor(strokeCol, mood.accentHigh, 0.24), map(rms, 0, 0.6, 20, 92));
    haloCol   = withAlpha(lerpColor(mood.glow, strokeCol, 0.45), map(high + rms, 0, 1.2, 18, 80));

    // Trigger particle explosion if we smash the boundary or simply run out of life.
    if (!exploded && (abs(x) > width/2f || abs(y) > height/2f)) {
      slamToNearestEdge();
      triggerExplosion();
    } else if (!exploded && life() >= lifeMs) {
      // Age-out should feel like a boundary detonation too.
      slamToNearestEdge();
      triggerExplosion();
    }
  }

  // Life helpers
  float   life()     { return millis() - born; }
  float   normLife() { return constrain(life() / lifeMs, 0, 1); }
  boolean dead()     { return life() > lifeMs; }

  // Rough complexity metric used to size particle bursts
  int complexity() { return 60; }

  // Snap toward the nearest boundary so the explosion reads like a wall hit.
  void slamToNearestEdge() {
    float halfW = width / 2f;
    float halfH = height / 2f;
    float distLeft   = halfW + x;
    float distRight  = halfW - x;
    float distTop    = halfH + y;
    float distBottom = halfH - y;
    float minDist = min(min(distLeft, distRight), min(distTop, distBottom));

    if (minDist == distLeft) {
      x = -halfW;
    } else if (minDist == distRight) {
      x = halfW;
    } else if (minDist == distTop) {
      y = -halfH;
    } else {
      y = halfH;
    }
  }

  // Common explosion trigger — spawns dust and schedules a quick removal.
  void triggerExplosion() {
    exploded = true;
    explode(this);
    lifeMs = max(life(), 1); // keep normLife() sane but mark for removal next frame
  }

  void drawAura(float rx, float ry) {
    float t = normLife();
    float pulse = 1.0 + 0.08 * sin(frameCount * 0.06f + seed);
    pushStyle();
    blendMode(ADD);
    noStroke();
    fill(withAlpha(haloCol, (1.0 - t) * 24));
    ellipse(0, 0, rx * 2.3 * pulse, ry * 2.1 * pulse);
    fill(withAlpha(strokeCol, (1.0 - t) * 12));
    ellipse(0, 0, rx * 1.35 * pulse, ry * 1.35 * pulse);
    popStyle();
  }

  // Subclasses must implement their own draw()
  abstract void draw();
}

// ── Form 1: PolygonBurst ─────────────────────────────────────────────────────
// A many-sided polygon whose vertices jitter via noise + alternating offsets.
// Interior “wiring” lines add complexity.
class PolygonBurst extends GlitchForm {
  int   sides  = (int)random(7, 23);
  float radius = random(80, 260);

  void draw() {
    pushMatrix(); pushStyle();
    translate(x, y);
    rotate(rot);

    float t    = normLife(); // 0 → 1 across lifespan
    float rNow = radius * (1.0 + 0.6 * sin(TWO_PI * (t + random(0.01))));
    drawAura(rNow * 0.9, rNow * 0.9);

    // Choose a bright blend mode for glow
    if (additive) blendMode(ADD); else blendMode(SCREEN);

    // Outline polygon with jitter
    noFill();
    stroke(strokeCol);
    strokeWeight(map(t, 0, 1, 3, 0.6)); // thin out as it dies

    beginShape();
    randomSeed(seed); // stable per-instance wobble
    for (int i = 0; i < sides; i++) {
      float a      = TWO_PI * i / sides;
      float jitter = noise(i*0.2, frameCount*0.03) * 35 * (1.8 - t); // fade jitter over life
      float rr     = rNow + jitter + (i % 2 == 0 ? 18 : -18);        // alternating spikes
      vertex(rr * cos(a), rr * sin(a));
    }
    endShape(CLOSE);

    // Interior cross-lines for extra structure (light, semi-random)
    stroke(255, 30);
    for (int k = 0; k < sides/3; k++) {
      int i1 = (int)random(sides), i2 = (int)random(sides);
      float a1 = TWO_PI * i1 / sides;
      float a2 = TWO_PI * i2 / sides;
      line(rNow*cos(a1), rNow*sin(a1), rNow*cos(a2), rNow*sin(a2));
    }

    popStyle(); popMatrix();
  }

  int complexity() { return sides; }
}

// ── Form 2: WireLissajous ────────────────────────────────────────────────────
// A dense wireframe Lissajous curve (ax, ay frequencies). It morphs over time,
// jitters slightly, and adds cross-threads for lattice complexity.
class WireLissajous extends GlitchForm {
  float ax = random(2, 9), ay = random(2, 9); // curve frequencies
  float phase = random(TWO_PI);
  int   pts   = 500;

  void draw() {
    pushMatrix(); pushStyle();
    translate(x, y);
    rotate(rot);

    blendMode(ADD);
    noFill();
    stroke(strokeCol);
    strokeWeight(1.5);

    float t = normLife();
    float s = 120 + 220 * (1.0 - t); // shrink over life
    drawAura(s * 0.85, s * 0.85);

    // Main path
    beginShape();
    for (int i = 0; i < pts; i++) {
      float u  = map(i, 0, pts-1, 0, TWO_PI);
      float px = s * sin(ax * u + phase + t*8) + random(-2, 2) * (1.5 - t);
      float py = s * sin(ay * u + t*6)         + random(-2, 2) * (1.5 - t);
      vertex(px, py);
    }
    endShape();

    // Cross threads (faint)
    stroke(255, 40);
    for (int k = 0; k < 20; k++) {
      float u1 = random(TWO_PI), u2 = random(TWO_PI);
      float px1 = s * sin(ax*u1 + phase), py1 = s * sin(ay*u1);
      float px2 = s * sin(ax*u2 + phase), py2 = s * sin(ay*u2);
      line(px1, py1, px2, py2);
    }

    popStyle(); popMatrix();
  }

  int complexity() { return pts / 2; }
}

// ── Form 3: NoisyDonut ───────────────────────────────────────────────────────
// A torus-like “donut” constructed from triangle strips. The outer radius
// wiggles per segment; the inner “tube” oscillates → complex woven look.
class NoisyDonut extends GlitchForm {
  int   ribs = (int)random(20, 48); // how many donut slices
  float r1   = random(80, 160);     // base outer radius
  float r2   = random(26, 60);      // tube radius
  float angularWarp = random(0.12f, 0.42f);
  float ribNoiseScale = random(0.09f, 0.22f);
  float phaseDrift = random(TWO_PI);

  void draw() {
    pushMatrix(); pushStyle();
    translate(x, y);
    rotate(rot);

    blendMode(SCREEN);
    noStroke();

    float t   = normLife();
    float rr1 = r1 * (1.0 + 0.25 * sin(frameCount*0.07));
    float rr2 = r2 * (1.0 + 0.4  * sin(frameCount*0.11 + seed));
    drawAura(rr1 * 0.95, rr1 * 0.95);

    float angleCursor = 0;
    for (int i = 0; i < ribs; i++) {
      float step1 = TWO_PI / ribs * (0.62f + 0.92f * noise(seed * 0.0001f + i * ribNoiseScale, t * 5 + frameCount * 0.01f));
      float step2 = TWO_PI / ribs * (0.62f + 0.92f * noise(seed * 0.0002f + (i + 1) * ribNoiseScale, t * 5 + frameCount * 0.01f));
      float a   = angleCursor + angularWarp * sin(frameCount * 0.03f + phaseDrift + i * 0.35f);
      angleCursor += step1;
      float a2  = angleCursor + angularWarp * sin(frameCount * 0.03f + phaseDrift + i * 0.35f + 0.9f);

      // Per-slice noise to deform outer radius
      float n1  = noise(i * ribNoiseScale,         frameCount * 0.02f + seed * 0.00003f) * 46 * (1.4 - t);
      float n2  = noise((i + 1) * ribNoiseScale,   frameCount * 0.02f + seed * 0.00003f) * 46 * (1.4 - t);

      float R1 = rr1 + n1, R2 = rr1 + n2;

      // Color gradient around the ring (lerp to a highlight)
      int c = lerpColor(fillCol, color(255, 80), (float)i / ribs);
      fill(c);

      // Build one “rib” as a small triangle strip along the tube angle
      beginShape(TRIANGLE_STRIP);
      for (int k = 0; k <= 6; k++) {
        float phi = map(k, 0, 6, 0, TWO_PI) + 0.3f * sin(i * 0.24f + k * 0.8f + phaseDrift + t * 10);
        float ar  = lerp(a, a2 + step2 * 0.2f, k / 6.0f);
        float skew = 1.0f + 0.18f * sin(ar * 3.0f + phaseDrift);
        float x1 = (R1 + rr2 * cos(phi) * skew) * cos(ar);
        float y1 = (R1 + rr2 * cos(phi) * skew) * sin(ar);
        float x2 = (R2 + rr2 * cos(phi) / skew) * cos(a2);
        float y2 = (R2 + rr2 * cos(phi) / skew) * sin(a2);
        vertex(x1, y1);
        vertex(x2, y2);
      }
      endShape();
    }

    popStyle(); popMatrix();
  }

  int complexity() { return ribs * 7; }
}

// ── Form 4: TriStripWeave ────────────────────────────────────────────────────
// Concentric triangle strips whose radii wobble with different harmonics,
// forming a vibrating woven disk.
class TriStripWeave extends GlitchForm {
  int strips = (int)random(8, 16);
  int segs   = 120;

  void draw() {
    pushMatrix(); pushStyle();
    translate(x, y);
    rotate(rot);

    blendMode(ADD);
    stroke(strokeCol);
    noFill();

    float t = normLife();
    drawAura(90 + strips * 16, 90 + strips * 16);

    for (int s = 0; s < strips; s++) {
      float rad = 60 + s*16 + 20 * sin((frameCount + s*9) * 0.06);
      float wob = 12 + 30 * noise(s*0.2, frameCount*0.03);

      beginShape(TRIANGLE_STRIP);
      for (int i = 0; i <= segs; i++) {
        float u  = map(i, 0, segs, 0, TWO_PI);
        float r1 = rad + wob * sin(u * (3 + s%5) + t*10);
        float r2 = rad + wob * cos(u * (2 + s%7) - t*9);
        vertex(r1 * cos(u),          r1 * sin(u));
        vertex(r2 * cos(u + 0.02f),  r2 * sin(u + 0.02f));
      }
      endShape();
    }

    popStyle(); popMatrix();
  }

  int complexity() { return strips * segs; }
}

// ── Form 5: SpiroSpline ──────────────────────────────────────────────────────
// Hypotrochoid-like spirograph curve with occasional “tears” (pen-up breaks).
class SpiroSpline extends GlitchForm {
  int   pts = 900;
  float R = random(120, 220), r = random(12, 60), p = random(10, 80);
  float stepBase = random(0.022f, 0.05f);
  float angularWarp = random(0.12f, 0.45f);
  float radialWarp = random(0.08f, 0.28f);
  float phaseDrift = random(TWO_PI);

  void draw() {
    pushMatrix(); pushStyle();
    translate(x, y);
    rotate(rot);

    blendMode(ADD);
    noFill();
    stroke(strokeCol);
    strokeWeight(1.3);

    float t = normLife();
    drawAura(R * 0.85 + p, R * 0.85 + p);

    beginShape();
    float u = 0;
    for (int i = 0; i < pts; i++) {
      u += stepBase * (0.65f + 1.25f * noise(seed * 0.0002f + i * 0.014f, frameCount * 0.008f + t * 2.7f));
      float a = u + t * 14;
      float bend = angularWarp * sin(a * 0.65f + phaseDrift) + angularWarp * 0.55f * (noise(i * 0.02f + phaseDrift, t * 3.5f) - 0.5f);
      float q = a + bend;
      float radiusScale = 1.0f + radialWarp * sin(q * 1.7f + phaseDrift) + radialWarp * 0.7f * (noise(i * 0.012f + seed * 0.0003f, frameCount * 0.006f) - 0.5f);
      float px = ((R - r) * cos(q) + p * cos(((R - r) / r) * q + bend * 0.8f)) * radiusScale;
      float py = ((R - r) * sin(q) - p * sin(((R - r) / r) * q + bend * 0.5f)) * radiusScale;

      // “Tearing” jitter declines over life
      px += random(-3, 3) * (1.8 - t);
      py += random(-3, 3) * (1.8 - t);

      // Occasionally break the path (like a skipping pen)
      if (random(1) < 0.01) { endShape(); beginShape(); }

      vertex(px, py);
    }
    endShape();

    popStyle(); popMatrix();
  }

  int complexity() { return pts; }
}

// ── KEYBOARD CONTROLS (simple show-time interface) ───────────────────────────
void keyPressed() {
  if (key == ' ') {                     // force a form spawn
    spawnForm();
  }
  if (key == 's' || key == 'S') {       // save a still frame
    saveFrame("glitch-####.png");
  }
  if (key == 'c' || key == 'C') {       // toggle RGB split
    doRGBShift = !doRGBShift;
  }
  if (key == 'f' || key == 'F') {       // toggle feedback
    doFeedback = !doFeedback;
  }
  if (key == 'g' || key == 'G') {       // toggle fade floor
    doFadeFloor = !doFadeFloor;
  }
  if (key == 'b' || key == 'B') {       // toggle beat-linked strobe
    strobeBeatLinked = !strobeBeatLinked;
    if (strobeBeatLinked) strobeCountdown = strobeHoldFrames;
  }
  if (key == 'v' || key == 'V') {       // cycle palette mood
    cyclePalette();
  }
  if (key == 'o' || key == 'O') {       // toggle framing overlay
    cinematicOverlay = !cinematicOverlay;
  }
  if (key == '[')  strobeIntensity = max(0,   strobeIntensity - 0.05);
  if (key == ']')  strobeIntensity = min(1,   strobeIntensity + 0.05);
  if (key == '-')  fbAmount        = max(0,   fbAmount - 0.04);
  if (key == '=')  fbAmount        = min(1,   fbAmount + 0.04);
  if (key == ',')  fbRotate       -= 0.002;
  if (key == '.')  fbRotate       += 0.002;
  if (key == ';')  fbZoom          = max(0.95, fbZoom - 0.002);
  if (key == '\'') fbZoom          = min(1.05, fbZoom + 0.002);
  if (key == 'p' || key == 'P') {       // save preset
    savePreset();
  }
  if (key == 'l' || key == 'L') {       // load latest preset
    loadMostRecentPreset();
  }
  if (key == 'i' || key == 'I') {       // show/hide instructions
    showHelp = !showHelp;
  }
}
