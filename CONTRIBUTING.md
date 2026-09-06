# Contributing

Thank you. The bar is the same as for the rest of the family: one thing, plainly explained, nothing recorded, nothing leaves the Mac.

- Build with `./build-app.sh`; the Command Line Tools are enough.
- Run `ampmac selftest` and `tests/integration.sh` before a pull request. The tests feed the chain synthesised hits and chords and never open an audio device, so they run on a headless runner.
- A new preset goes in `Presets.swift` under its genre, named for a room, a town or a year, never a trademark, a studio, a band or a record; run `ampmac loudness` and set its trim so it lands at unity. The chord engine is chordmap; improvements to the hearing belong there. A new stage in the chain goes in `DSP.swift` with a test that shows it doing its one thing.
- Anything that records, uploads, or phones home will not be merged.

MIT licensed; contributions are accepted under the same license.
