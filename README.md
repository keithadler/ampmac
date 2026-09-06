# Amp for Mac

A drum amp for the input of your audio interface, and an Ear that tells you the key, the chords and where the capo goes. It listens to one input and plays to one output. Nothing is recorded, nothing leaves the Mac.

## Download

**[Download Amp-for-Mac-1.0.0.dmg](https://github.com/keithadler/ampmac/releases/latest/download/Amp-for-Mac-1.0.0.dmg)** (macOS 14 or later, Apple Silicon and Intel)

Open the DMG, drag the app to Applications, open it. The first time, macOS says the app is from an unidentified developer: right-click the app, choose Open, then Open again. That is once.

Two permissions, each asked for once, each explained in the dialog: **Microphone**, because macOS treats an interface input as a microphone and the amp cannot hear the drums without it; and **System Audio Recording**, only if you use the Ear on the Mac's own sound. The app records nothing with either.

![Amp for Mac](docs/screenshots/amp.png)

## The amp

Plug a mic or a trigger into the interface, press the power button, play. The chain is what a drum channel on a desk does, in order: a gate with hold, an attack and sustain shaper, a compressor with a mix knob for parallel squash, three-band tone with a rumble filter, drive, a stereo room that can cut with the gate, and a limiter half a dB under full. Every knob glides, so presets switch while you play.

Seventeen presets: seven rooms (Clean Kit, Tight Pop, Rock Room, Garage, Arena, Dry Punch, Lo-fi) and ten sounds people know by ear (Levee Stairwell, In the Air, Motown, Abbey Road, Nevermind, Boom Bap, Blue Note, Tight Metal, Dead 70s, Disco). Save your own beside them; ⌘1 to ⌘9 jump between the first nine.

A level guide reads the raw input and says which way to turn the gain knob on the interface. Auto level then trims the amp's own input gain so hits land near -10 dB. Clipping at the interface is the knob's job, and the guide says so.

Round trip on a Scarlett Solo is a few milliseconds: two buffers plus what the interface reports. 128 frames is the default; 64 is fine on Apple Silicon. The number is in the status line.

## The Ear

![The Ear](docs/screenshots/ear.png)

Switch to Ear, press the ear, play a song on the Mac. It names each chord as it goes by, works out the key after a few bars, and lists where a capo goes so the open shapes play it (Eb: capo 3, play in C). Pick a capo and every chord shown becomes the shape your hand makes. It can also listen to an input, so a guitar into the interface works too.

Every listen is kept, with its key and chords, in the sidebar. Retitle it, reopen it, delete it. The list lives in `~/Library/Application Support/Amp for Mac/listens.json` and nowhere else.

The Ear hears chords the way a tuner hears pitch: well on a clear mix, less well on a wall of distortion, and it does not know a song's name. Hearing the Mac's own sound needs macOS 14.2 or later.

## Honest limits

- It is a standalone amp, not a plugin. It will not load in Logic or Live.
- Turn the interface's direct-monitor knob or switch off, or you hear the dry kit and the amp together.
- Latency is the interface's. A USB interface at 128 frames is about 5 to 8 ms round trip; the Mac's built-in input and speakers are slower and feed back.
- The limiter keeps the output under full scale; it cannot un-clip an input that arrived clipped.
- The Ear has no idea what song is playing, only what key and chords it hears.

## Command line

`ampmac` is linked into your PATH by the installer, or call `/Applications/Amp\ for\ Mac.app/Contents/MacOS/AmpMac`.

```
ampmac status                          devices chosen, latency, permissions
ampmac devices                         every audio device
ampmac presets [<name>]                the presets, or one preset's knobs as JSON
ampmac run --preset "Rock Room"        the amp from the terminal, meters and level advice once a second
ampmac render kit.wav out.wav --preset Garage
ampmac tone kit.wav                    a synthesised kit to try the amp with; --chords writes C G Am F
ampmac chords song.wav [--capo 3]      the Ear on a recording
ampmac ear [--source mac|Scarlett]     the Ear live
ampmac selftest                        the built-in tests
```

`--json` everywhere. Exit codes: 0 fine, 1 something to look at, 2 problem, 64 usage.

## Building

Swift Package, macOS 14 or later, the Command Line Tools are enough.

```
./build-app.sh --install
```

`./make-local-identity.sh` once makes a local signing certificate so permissions survive rebuilds. `ampmac selftest` and `tests/integration.sh` run the tests; the tests feed the chain synthesised hits and chords and never open a device.

## Privacy

See [PRIVACY.md](PRIVACY.md). The short version: the microphone permission is for hearing the interface, the system-audio permission is for the Ear, and neither records anything. The only connection the app ever makes is the optional daily check of the GitHub releases page for a new version.

## License

MIT. Made by Keith Adler. More from the same maker at [keithadler.github.io](https://keithadler.github.io).
