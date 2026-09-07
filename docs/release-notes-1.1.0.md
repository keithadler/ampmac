**[Download Amp-for-Mac-1.1.0.dmg](https://github.com/keithadler/ampmac/releases/latest/download/Amp-for-Mac-1.1.0.dmg)** (macOS 14 or later, Apple Silicon)

Open the DMG, drag the app to Applications, open it. The first time, macOS says the app is from an unidentified developer: right-click the app, choose Open, then Open again. That is once.

## A guitar amp

Switch the window to Guitar and it is an amp: gain, bass, middle, treble, presence, master, sag, a noise gate, a room, and a speaker to play it through. Twenty-four presets in seven kinds — Clean, Crunch, Lead, Metal, Blues, Country and Indie — named for the room, the town and the year.

The speaker is the part that matters. A distorted guitar with no cabinet is a wasp in a tin: it is all the energy above five kilohertz that a twelve-inch driver cannot make. Five cabinets are offered — 4×12, 2×12, 1×12, 1×8, and none at all — each built from a low cut, a resonance, the cone dip that gives a speaker its voice, a presence peak, and the fall a real driver has above about five kilohertz. Nothing here is a recording of a cabinet; it is filters shaped like one, so the app still ships with no assets in it.

Inside, two clipping stages with the bass cut before the dirt rather than after, which is what keeps a high gain sound tight instead of muddy; a tone stack whose controls pull against each other the way a passive one does, where scooping the middle takes the level with it; and a power amp that clips more softly than the preamp and sags under a big chord. The clipping runs at twice the sample rate, so the harmonics distortion makes above half the sample rate do not fold back down as tones nobody played.

## An acoustic, played as an electric

Plug an acoustic in and the app can tell. A magnetic pickup is a coil, and a coil cannot make much above five kilohertz; a piezo under the saddle has real energy at eight and twelve. It decides by listening, only while you are playing, and slowly enough that it never changes its mind mid-bar. Set it by hand instead if you would rather.

When it hears an acoustic, it makes it look like a magnetic pickup before the amp sees it: the body boom under a hundred hertz comes off, the hard quack around three and a half kilohertz that turns to broken glass the moment you distort it is taken out, the air above five kilohertz goes, a coil's own resonance goes on in their place, and the spike of the pick is rounded into a swell. One knob moves that resonance from a neck pickup to a bridge. Everything after it is the ordinary amp.

## Everything else

The drum amp is unchanged, and a preset saved in 1.0.0 still loads exactly as it did. Nothing leaves the Mac, nothing is recorded, and the app is still MIT licensed and free.
