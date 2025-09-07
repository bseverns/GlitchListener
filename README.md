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

The sketch comes with a key-mashing interface: spawn shapes, crank the feedback, toggle strobe madness.  Dive into `glitchListen.pde` for the full rundown and tweak what screams at you.

## Closing time

The sketch ships with a `stop()` that cleans up Minim so the audio driver doesn’t get wedged.  If you’re hacking on this and things hang on exit, double-check that you’re calling `super.stop()` after your own cleanup.

## Contribute or fork off

Got ideas?  Fork it, make it weirder, and send a PR.  Or don’t.  Punk rock means doing your own thing.

