# GlitchListener

Welcome to the **Glitch Geometry Listener (XL)** – a full-blown, audio-reactive spectacle built in [Processing](https://processing.org/).  It's here to teach, provoke, and maybe blow up your monitors (metaphorically).  The sketch sniffs your mic or loopback, analyses the incoming noise with Minim, and then sprays the screen with a swarm of short-lived geometric oddities.

## Why this exists

Because audio visualisation doesn’t have to be safe or polite.  This code doubles as a lesson plan: every block is explained and commented so you can hack, remix, or wreck it and learn something along the way.

## Running the beast

1. Grab Processing 3+ and install the **Minim** and **OSC** libraries.
2. Drop this folder into your sketchbook and mash `Run`.
3. Pump some sound in – mic, synth, your neighbour’s droning fridge.

## Controls

Here's your live rig cheat sheet—no mysteries, just hot keys:

* `SPACE` – spawn a form on demand.
* `C` – toggle RGB split glitching.
* `F` – switch the feedback smear.
* `G` – fade the floor to black.
* `B` – beat-driven strobe.
* `[ / ]` – strobe intensity down/up.
* `- / =` – feedback amount down/up.
* `, / .` – feedback rotation.
* `; / '` – feedback zoom.
* `P` – save a preset JSON to `data/`.
* `L` – load the freshest preset.
* `S` – grab a `saveFrame()` screenshot.
* `I` – hide or show the on-screen help box squatting in the lower-right 250×250 patch.

Shapes now pop in from jittery starting points all over the field—never jailed in one corner—before wandering off like caffeinated fireflies.

### How the chaos triggers

An FFT chews up the incoming sound and watches the bass, mids, and highs. When any band spikes hard enough, a form tied to that part of the spectrum barges in. Bass hits birth chunky polygons, mids swirl donuts or splines, and highs scribble wiry Lissajous loops. The stage now allows up to **16** forms at once so no riff gets left behind.

As each form ages it feels the tug of an invisible galactic drain.  The closer it gets to dying, the harder it's yanked toward the nearest edge.  Smack into the boundary and it goes supernova, spraying a cloud of tiny motes whose count nods to the form's own vertex guts.  Those motes chill out over time, drifting into a hazy floor that hangs behind the action so the whole mess has a ghostly ground to stomp on.

## Closing time

The sketch ships with a `stop()` that cleans up Minim so the audio driver doesn’t get wedged.  If you’re hacking on this and things hang on exit, double-check that you’re calling `super.stop()` after your own cleanup.

## Contribute or fork off

Got ideas?  Fork it, make it weirder, and send a PR.  Or don’t.  Punk rock means doing your own thing.

