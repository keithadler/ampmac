# Changelog

## 1.1.0, 2026-09-07

A guitar amp, and an acoustic that can be played as an electric.

Switch the window to Guitar and it is an amp: gain, bass, middle, treble, presence, master, sag, a gate, a room and a speaker. Two clipping stages with the bass cut before the dirt rather than after, so a high gain sound stays tight. A tone stack whose controls pull against each other the way a passive one does. A power amp that clips more softly than the preamp and sags under a big chord. Five cabinets, none of them a recording: a low cut, a resonance, the cone dip that gives a driver its voice, a presence peak, and the fall above five kilohertz that is the difference between an amp and a wasp in a tin. The clipping runs at twice the sample rate, so the harmonics it makes above half the sample rate do not fold back down as tones nobody played. Twenty-four presets in seven kinds, each trimmed to land within a decibel of what went in.

It also tells which guitar is plugged in, by listening: a coil cannot make much above five kilohertz and a piezo makes plenty. It only judges while you are playing and takes two seconds to change its mind, and you can set it by hand instead. When it hears an acoustic, it makes it look like a magnetic pickup before the amp sees it, so every preset and speaker behaves as it does for an electric.

## 1.0.0, 2026-09-06

First release. A drum amp for the input of an audio interface: gate, attack and sustain shaper, compressor with parallel mix, three-band tone, drive, a room that can cut with the gate, and a limiter, with thirty-nine presets in twelve genres, each trimmed to one loudness, and your own saved beside them. A level guide says which way to turn the interface's gain knob and auto level trims the rest. The Ear, chordmap linked in, listens to the Mac's own sound or an input, names the chords bar by bar with the key, tempo and sections, picks the capo, and keeps every listen with its chord sheet. Command line for all of it, including offline rendering and chord reading of recordings.
