# Privacy

Amp for Mac listens to one audio input and plays to one output, in memory, sample by sample. It writes no audio to disk, ever. The microphone permission macOS asks for is how macOS describes an interface input; the app cannot hear the interface without it.

The Ear, when set to the Mac's own sound, uses a Core Audio tap (the same mechanism as the system's own audio routing) to read what the Mac is playing. macOS asks once for system audio recording. The Ear keeps twelve numbers per quarter second and the chord names it decides on, in memory; the list of listens (title, time, key, chords) is saved in `~/Library/Application Support/Amp for Mac/listens.json`. Delete the file and the history is gone. No sound is stored.

Presets and settings live in the app's own defaults. Nothing is sent anywhere. The only connection the app opens is the optional daily update check, which asks GitHub for the version number of the latest release and sends nothing about you. No analytics, no crash reporting, no account.
