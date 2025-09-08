# GlitchListener

Welcome to the **Glitch Geometry Listener (XL)** – a full-blown, audio-reactive spectacle built in [Processing](https://processing.org/).  It's here to teach, provoke, and maybe blow up your monitors (metaphorically).  The sketch sniffs your mic or loopback, analyses the incoming noise with Minim, and then sprays the screen with a swarm of short-lived geometric oddities.

## Why this exists

Because audio visualisation doesn’t have to be safe or polite.  This code doubles as a lesson plan: every block is explained and commented so you can hack, remix, or wreck it and learn something along the way.

## Running the beast

1. Grab Processing 3+ and install the **Minim** and **OSC** libraries.
2. Drop this folder into your sketchbook and mash `Run`.
3. Pump some sound in – mic, synth, your neighbour’s droning fridge.

### Mac users – read this
If you run into a cranky stack trace ending with something like:

```
java.lang.RuntimeException: Waited 5000ms for: <18f71a5, f488fe4>[count 2, qsz 0, owner <main-FPSAWTAnimator#00-Timer0>] - <main-FPSAWTAnimator#00-Timer0-FPSAWTAnimator#00-Timer1>
```

You're hitting a JOGL windowing deadlock.  It often shows up on macOS when OpenGL/NSWindow can't spin up fast enough.  Try these tricks:

* Launch Processing with the `--force` flag for the OpenGL renderer.
* Make sure no other full-screen apps are hogging the GPU.
* As a last resort, add `-Djava.awt.headless=true` when running from the CLI.

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

Shapes now burst into existence dead-center before wandering off like caffeinated fireflies.

As each form ages it feels the tug of an invisible galactic drain.  The closer it gets to dying, the harder it's yanked toward the nearest edge.  Smack into the boundary and it goes supernova, spraying a cloud of tiny motes whose count nods to the form's own vertex guts.  Those motes chill out over time, drifting into a hazy floor that hangs behind the action so the whole mess has a ghostly ground to stomp on.

## Closing time

The sketch ships with a `stop()` that cleans up Minim so the audio driver doesn’t get wedged.  If you’re hacking on this and things hang on exit, double-check that you’re calling `super.stop()` after your own cleanup.

## Contribute or fork off

Got ideas?  Fork it, make it weirder, and send a PR.  Or don’t.  Punk rock means doing your own thing.

