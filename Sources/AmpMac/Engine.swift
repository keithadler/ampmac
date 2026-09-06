//  Amp for Mac — MIT licensed. See LICENSE.
//
//  Live audio: one HAL output unit with input enabled, the chain in its render callback. When the
//  input and output are different devices, a private aggregate device joins them for the run and
//  is destroyed on stop. Nothing is written to disk.

import Foundation
import AudioToolbox
import CoreAudio
import AVFoundation

/// Knob values cross from the main thread to the audio thread here. A lock the audio thread only
/// tries, never waits on.
final class ParamBox: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var pending: AmpParams?
    func set(_ p: AmpParams) { os_unfair_lock_lock(&lock); pending = p; os_unfair_lock_unlock(&lock) }
    func take() -> AmpParams? {
        guard os_unfair_lock_trylock(&lock) else { return nil }
        defer { os_unfair_lock_unlock(&lock) }
        let p = pending; pending = nil; return p
    }
}

/// Meters the audio thread writes and the window reads thirty times a second.
final class Meters: @unchecked Sendable {
    var inPeak: Float = 0, outPeak: Float = 0, gateOpen = false, compGr: Float = 0, limiterGr: Float = 0
    var frames: UInt64 = 0, dropouts: UInt32 = 0
    func reset() { inPeak = 0; outPeak = 0; gateOpen = false; compGr = 0; limiterGr = 0; frames = 0; dropouts = 0 }
}

struct EngineError: LocalizedError { let message: String; var errorDescription: String? { message } }

final class Engine: @unchecked Sendable {
    static let shared = Engine()
    let chain = Chain()
    let params = ParamBox()
    let meters = Meters()
    private(set) var running = false
    private(set) var sampleRate: Double = 48000
    private(set) var bufferFrames = 128
    private(set) var input: AudioDevice?, output: AudioDevice?
    private(set) var inputChannel = 0
    private var unit: AudioUnit?
    private var aggregate: AudioDeviceID = 0
    private var inputList: UnsafeMutableAudioBufferListPointer?
    private var inputChannels = 0, outputChannels = 2, outputOffset = 0
    private var scratch: [Float] = []
    static let maxFrames = 4096

    /// The engine's own audio thread; nothing else touches `chain` while running.
    private static let render: AURenderCallback = { refCon, flags, timestamp, _, frames, ioData in
        let e = Unmanaged<Engine>.fromOpaque(refCon).takeUnretainedValue()
        return e.render(flags: flags, timestamp: timestamp, frames: frames, ioData: ioData)
    }

    private func render(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, timestamp: UnsafePointer<AudioTimeStamp>, frames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let ioData, let unit, let inputList else { return noErr }
        let n = Int(frames)
        let out = UnsafeMutableAudioBufferListPointer(ioData)
        for b in out { memset(b.mData, 0, Int(b.mDataByteSize)) }
        for i in 0..<inputList.count { inputList[i].mDataByteSize = UInt32(n * 4) }
        let status = AudioUnitRender(unit, flags, timestamp, 1, frames, inputList.unsafeMutablePointer)
        guard status == noErr, n <= Engine.maxFrames else { meters.dropouts &+= 1; return noErr }
        if let p = params.take() { chain.apply(p) }
        let ch = min(inputChannel, inputList.count - 1)
        guard ch >= 0, let src = inputList[ch].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        let l = outputOffset, r = outputOffset + 1
        guard l < out.count, let lp = out[l].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        let rp = r < out.count ? out[r].mData?.assumingMemoryBound(to: Float.self) : nil
        scratch.withUnsafeMutableBufferPointer { sp in
            chain.process(input: src, outL: lp, outR: rp ?? sp.baseAddress!, frames: n)
        }
        meters.inPeak = chain.inPeak; meters.outPeak = chain.outPeak; meters.gateOpen = chain.gateOpen
        meters.compGr = chain.compGr; meters.limiterGr = chain.limiterGr; meters.frames &+= UInt64(n)
        return noErr
    }

    // MARK: Start and stop

    static func microphoneAllowed() -> AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }
    static func requestMicrophone() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }

    func start(input inDev: AudioDevice, output outDev: AudioDevice, inputChannel ch: Int, bufferFrames wanted: Int, params p: AmpParams) throws {
        if running { stop() }
        guard inDev.inputs > 0 else { throw EngineError(message: "\(inDev.name) has no inputs.") }
        guard outDev.outputs > 0 else { throw EngineError(message: "\(outDev.name) has no outputs.") }
        var device = inDev.id
        outputOffset = 0
        if inDev.uid != outDev.uid {
            device = try makeAggregate(input: inDev, output: outDev)
            outputOffset = inDev.outputs   // in the aggregate, the input device's own outputs come first
        }
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { throw EngineError(message: "No audio output unit.") }
        var au: AudioUnit?
        try check(AudioComponentInstanceNew(comp, &au), "open the audio unit")
        guard let au else { throw EngineError(message: "No audio unit.") }
        unit = au
        var on: UInt32 = 1
        try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, 4), "enable input")
        try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &on, 4), "enable output")
        var dev = device
        try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, UInt32(MemoryLayout<AudioDeviceID>.size)), "use \(inDev.name)")
        // Buffer size on the device, then read back what it accepted.
        var frames = UInt32(max(32, min(wanted, Engine.maxFrames)))
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSize, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(device, &addr, 0, nil, 4, &frames)
        bufferFrames = Int(Devices.uint(device, kAudioDevicePropertyBufferFrameSize, scope: kAudioObjectPropertyScopeGlobal))
        if bufferFrames == 0 { bufferFrames = Int(frames) }
        sampleRate = Devices.sampleRate(device); if sampleRate == 0 { sampleRate = inDev.sampleRate }
        inputChannels = max(Devices.channels(device, scope: kAudioObjectPropertyScopeInput), 1)
        outputChannels = max(Devices.channels(device, scope: kAudioObjectPropertyScopeOutput), 1)
        inputChannel = min(max(ch, 0), inputChannels - 1)
        var inFmt = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved, mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: UInt32(inputChannels), mBitsPerChannel: 32, mReserved: 0)
        try check(AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &inFmt, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "set the input format")
        var outFmt = inFmt; outFmt.mChannelsPerFrame = UInt32(outputChannels)
        try check(AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &outFmt, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "set the output format")
        var maxFrames = UInt32(Engine.maxFrames)
        AudioUnitSetProperty(au, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, 4)
        let list = AudioBufferList.allocate(maximumBuffers: inputChannels)
        for i in 0..<inputChannels {
            list[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(Engine.maxFrames * 4), mData: UnsafeMutableRawPointer.allocate(byteCount: Engine.maxFrames * 4, alignment: 16))
        }
        inputList = list
        scratch = [Float](repeating: 0, count: Engine.maxFrames)
        chain.prepare(sampleRate: Float(sampleRate)); chain.apply(p)
        meters.reset()
        var cb = AURenderCallbackStruct(inputProc: Engine.render, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try check(AudioUnitSetProperty(au, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "set the render callback")
        try check(AudioUnitInitialize(au), "initialise the audio unit")
        try check(AudioOutputUnitStart(au), "start audio")
        input = inDev; output = outDev; running = true
    }

    func stop() {
        if let au = unit { AudioOutputUnitStop(au); AudioUnitUninitialize(au); AudioComponentInstanceDispose(au) }
        unit = nil
        if let list = inputList { for b in list { b.mData?.deallocate() }; free(list.unsafeMutablePointer) }
        inputList = nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        running = false
    }

    private func check(_ s: OSStatus, _ what: String) throws {
        guard s != noErr else { return }
        stop()
        throw EngineError(message: "Could not \(what) (CoreAudio error \(s)).")
    }

    private func makeAggregate(input: AudioDevice, output: AudioDevice) throws -> AudioDeviceID {
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Amp for Mac",
            kAudioAggregateDeviceUIDKey: "com.keithadler.ampmac.aggregate.\(getpid())",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: output.uid,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: input.uid, kAudioSubDeviceDriftCompensationKey: 1], [kAudioSubDeviceUIDKey: output.uid]],
        ]
        var id: AudioDeviceID = 0
        let s = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &id)
        guard s == noErr, id != 0 else { throw EngineError(message: "Could not join \(input.name) and \(output.name) (CoreAudio error \(s)). Pick one interface for both.") }
        aggregate = id
        return id
    }

    var roundTripMs: Double {
        guard let input, let output else { return 0 }
        return Double(2 * bufferFrames + input.inLatency + output.outLatency) / max(sampleRate, 1) * 1000
    }
}
