//
//  ViewController.swift
//  AudioEngineDemo
//
//  Created by Josh Elkins on 11/15/20.
//

import UIKit
import AVFoundation


class AudioEngineViewController: UITableViewController {
    @IBOutlet weak var frequencySlider: UISlider!
    @IBOutlet weak var sineWaveSwitch: UISwitch!
    @IBOutlet weak var sineWaveVolumeSlider: UISlider!
    @IBOutlet weak var bpmSlider: UISlider!
    @IBOutlet weak var metronomeSwitch: UISwitch!
    @IBOutlet weak var metronomeVolumeSlider: UISlider!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var playButton: UIButton!

    let standardFormat = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!

    // A mp3 file containing a "tick" sound that is used by the metronome.
    // AVAudioFile is an object that represents the mp3 within AVFoundation.
    let tickFile: AVAudioFile = {
        let tickURL = Bundle.main.url(forResource: "tick", withExtension: "mp3")!
        return try! AVAudioFile(forReading: tickURL)
    }()

    // The AVAudioEngine itself.
    // The AVAudioEngine comes with an input node (for mic input),
    // an output node (for output to speakers, headphones, Bluetooth,
    // Airplay, etc.), and a main mixer node for connecting multiple
    // audio sources to the output node.
    var engine = AVAudioEngine()

    // The source node, which generates the sine wave tone,
    // and its mixer.
    var sourceNode: AVAudioSourceNode!
    var sourceMixerNode = AVAudioMixerNode()

    // The sink node, which receives audio input from iOS.
    var sinkNode: AVAudioSinkNode!

    // The metronome node, which is an instance of AVAudioPlayerNode
    // repeatedly playing a sound file, and its mixer.
    // metronomeBase is used to keep track of the audio player
    // time of the last metronome tick.
    var metronomePlayerNode = AVAudioPlayerNode()
    var metronomeMixerNode = AVAudioMixerNode()
    var metronomeBase: AVAudioFramePosition = 0

    // The recording player, which is also an AVAudioPlayerNode, is
    // used to play a sound buffer recorded from the input.
    // It also has its own mixer.
    var recordingPlayerNode = AVAudioPlayerNode()
    var recordingMixerNode = AVAudioMixerNode()
    var recordingBuffer: AVAudioPCMBuffer!

    // These properties are used for controlling certain properties of
    // audio system operation.  They use a thread-safe property wrapper
    // so they can be accessed by both the main thread and by
    // AVFoundation background and real-time rendering threads.
    // Note that blocking AVFoundation threads should be avoided if at
    // all possible.
    @Synchronized var isRecording = false
    @Synchronized var frequency = 100.0
    @Synchronized var bpm = 60.0

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Configure & activate the app's AVAudioSession.
        // AVAudioSession is your app's primary method of
        // configuring the audio system for your app's needs.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord)
            try session.setMode(.default)
            try session.setPreferredInputNumberOfChannels(1)
            try session.setActive(true)
        } catch {
            presentError(error)
        }

        // Also, get user permission to use the microphone if
        // it has not already been obtained.
        getRecordPermissionIfNeeded()
    }

    @IBAction func frequencySliderValueChanged(_ sender: UISlider) {
        setFrequency()
    }

    private func setFrequency() {
        frequency = Double(frequencySlider.value)
    }

    @IBAction func sinewaveSwitchValueChanged(_ sender: UISwitch) {
        setSinewaveVolume()
    }

    @IBAction func sinewaveVolumeSliderValueChanged(_ sender: UISlider) {
        setSinewaveVolume()
    }

    private func setSinewaveVolume() {
        // Set the volume per the slider, unless the switch is off.
        sourceMixerNode.outputVolume = sineWaveSwitch.isOn ? sineWaveVolumeSlider.value : 0.0
    }

    @IBAction func bpmSliderTouchUpInside(_ sender: UISlider) {
        setBPM()
    }

    private func setBPM() {
        // Adjust the instance var
        bpm = Double(bpmSlider.value)

        // Stop and restart the metronome player at the new
        // tempo
        metronomePlayerNode.stop()
        startMetronomePlayer()
    }

    @IBAction func metronomeVolumeSliderValueChanged(_ sender: UISlider) {
        setMetronomeVolume()
    }

    @IBAction func metronomeSwitchValueChanged(_ sender: UISwitch) {
        setMetronomeVolume()
    }

    private func setMetronomeVolume() {
        // Set the volume per the slider, unless the switch is off.
        metronomeMixerNode.outputVolume = metronomeSwitch.isOn ? metronomeVolumeSlider.value : 0.0
    }

    @IBAction func recordTapped(_ sender: Any) {
        isRecording.toggle()

        // Update the UI for the start or end of recording.
        let isRecording = self.isRecording
        playButton.isEnabled = !isRecording
        let recordButtonTitle = isRecording ? "Stop Recording" : "Start Recording"
        recordButton.setTitle(recordButtonTitle, for: .normal)

        // "Clear" the buffer at the start of recording by setting
        // its filled length to zero.
        if isRecording { recordingBuffer.frameLength = 0 }
    }

    @IBAction func playTapped(_ sender: Any) {
        // Tell the recording player note to play the recorded contents
        // of the buffer immediately.
        recordingPlayerNode.scheduleBuffer(recordingBuffer, completionHandler: {
            print("Finished playing recording")
        })
    }

    private func getRecordPermissionIfNeeded() {
        // AVAudioSession is used to get the state of permission
        // for use of the microphone, then to request permission
        // if needed.
        let session = AVAudioSession.sharedInstance()
        let micPermission = session.recordPermission
        if micPermission == .granted {
            startEngine()
        } else {
            session.requestRecordPermission { [weak self] granted in
                guard granted else { return }

                // If the user granted permission, start the engine.
                // startEngine() is called on the main thread because it
                // modifies some UIKit controls.
                DispatchQueue.main.async { self?.startEngine() }
            }
        }
    }

    private func configureEngine() {
        // Create a source node for generation of sine wave tones.
        setupSourceNode()

        // Create a sink node to accept microphone input.
        // The sink node's input should be the same format as the
        // input node's output, hence it is passed in.
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        setupSinkNode(inputFormat: inputFormat)

        // Attach all the nodes to the engine.  The input node,
        // output node, and main mixer node are created and attached
        // to the engine when the engine is created.
        engine.attach(sourceNode)
        engine.attach(sourceMixerNode)
        engine.attach(sinkNode)
        engine.attach(metronomePlayerNode)
        engine.attach(metronomeMixerNode)
        engine.attach(recordingPlayerNode)
        engine.attach(recordingMixerNode)

        // Connect all of the output chain nodes.
        // The engine automatically connects the main mixer node to the
        // output node.
        engine.connect(sourceNode, to: sourceMixerNode, format: standardFormat)
        engine.connect(sourceMixerNode, to: engine.mainMixerNode, format: nil)
        engine.connect(metronomePlayerNode, to: metronomeMixerNode, format: nil)
        engine.connect(metronomeMixerNode, to: engine.mainMixerNode, format: nil)
        engine.connect(recordingPlayerNode, to: recordingMixerNode, format: recordingBuffer.format)
        engine.connect(recordingMixerNode, to: engine.mainMixerNode, format: nil)

        // Connect the input chain nodes.  Just the input node & sink node.
        engine.connect(engine.inputNode, to: sinkNode, format: inputFormat)

        // Set audio parameters based on the positions of the controls
        setFrequency()
        setBPM()
        setSinewaveVolume()
        setMetronomeVolume()
    }

    private func startEngine() {
        // Attach nodes to the engine, connect nodes to each other,
        // and configure parameters
        configureEngine()

        do {
            // First, start the engine itself
            try engine.start()

            // Next, start the players.  No sound actually plays yet,
            // unless it was previously scheduled.
            startMetronomePlayer()
            startRecordingPlayer()
        } catch {
            // If engine start fails, show the error to the user
            presentError(error)
        }
    }

    // Create a source node to generate a sinewave and send it to the main mixer
    private func setupSourceNode() {
        // The `renderBlock` param contains timing info, plus a pointer to an
        // audio buffer that we can fill with audio for the engine to play
        // The contents of this buffer will be passed to the node that the
        // source node's output connects to
        sourceNode = AVAudioSourceNode(format: standardFormat, renderBlock: { (_, timeStamp, frameCount, audioBufferList) -> OSStatus in
            // Generate each audio sample, one by one
            // frameCount is the number of samples iOS expects from
            // our sink node
            for frame in 0..<Int(frameCount) {
                // Convert the exact time of this sample to seconds
                // then generate a point on the sine wave
                let absoluteFrame = timeStamp.pointee.mSampleTime + Double(frame)
                let time = absoluteFrame / Double(self.standardFormat.sampleRate)
                let sample = sin(2.0 * .pi * self.frequency * time)

                // Now write the sample into every channel
                // in the buffer
                let listPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
                for buffer in listPointer {
                    let bufferPointer = UnsafeMutableBufferPointer<Float>(buffer)
                    bufferPointer[frame] = Float(sample)
                }
            }
            return OSStatus(0)
        })
    }

    // Create a sink node to take audio input and expose it to us as data
    private func setupSinkNode(inputFormat: AVAudioFormat) {
        // Create a 30 second recording buffer to record audio data sent
        // into the sink
        recordingBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(inputFormat.sampleRate * 30))!
        recordingBuffer.frameLength = 0

        // The sink node's `receiverBlock` will be repeatedly called with
        // new audio data.  We take that data and write it piecemeal into
        // our recording buffer, as long as the `isRecording` flag is true.
        sinkNode = AVAudioSinkNode(receiverBlock: { [weak self] (_, audioFrameCount, audioBufferList) -> OSStatus in
            guard let self = self, self.isRecording else { return 0 }

            // Use unsafe memory access to copy the input audio buffer to
            // the right place in the recording buffer.
            withUnsafePointer(to: self.recordingBuffer.audioBufferList.pointee.mBuffers) { recordingAudioBufferArrayPtr in
                withUnsafePointer(to: audioBufferList.pointee.mBuffers) { sourceAudioBufferArrayPtr in
                    for i in 0..<1 {
                        let recordingAudioBuffer = (recordingAudioBufferArrayPtr + i)
                        let sourceAudioBuffer = (sourceAudioBufferArrayPtr + i)
                        recordingAudioBuffer.pointee.mData!.advanced(by: Int(recordingAudioBuffer.pointee.mDataByteSize)).copyMemory(from: sourceAudioBuffer.pointee.mData!, byteCount: Int(sourceAudioBuffer.pointee.mDataByteSize))
                    }
                }
            }
            // Advance the frame length of the buffer since it now contains
            // additional data.
            self.recordingBuffer.frameLength += audioFrameCount
            return 0  // no error
        })
    }

    private func startMetronomePlayer() {
        // Reset the metronome's timescale to zero
        metronomeBase = 0
        let startTime = AVAudioTime(sampleTime: 0, atRate: tickFile.fileFormat.sampleRate)

        // Schedule the first tick to play immediately
        self.metronomePlayerNode.scheduleFile(tickFile, at: startTime) { [weak self] in
            self?.rescheduleMetronome()
        }

        // Start the metronome player
        if engine.isRunning { metronomePlayerNode.play() }
    }

    // Start the recording buffer player (note that it will
    // play silence until audio is scheduled
    private func startRecordingPlayer() {
        recordingPlayerNode.play()
    }

    private func rescheduleMetronome() {
        // Get the current time for the metronome player, in the player's timescale.
        guard let renderTime = self.metronomePlayerNode.lastRenderTime, let playerTime = self.metronomePlayerNode.playerTime(forNodeTime: renderTime), playerTime.isSampleTimeValid else { return }

        // Advance metronomeBase by the number of audio frames
        // corresponding to the seconds between clicks.
        let framesPerSecond = AVAudioFramePosition(tickFile.fileFormat.sampleRate)
        metronomeBase += 60 * framesPerSecond / AVAudioFramePosition(bpm)

        // Create a new player time for the start of the next click,
        // and start the player.
        let startTime = AVAudioTime(sampleTime: metronomeBase, atRate: tickFile.fileFormat.sampleRate)
        self.metronomePlayerNode.scheduleFile(tickFile, at: startTime, completionHandler: { [weak self] in
            // Once a tick finishes playing, call this func again
            // to schedule the next click
            self?.rescheduleMetronome()
        })
    }

    // Show the user an error message.
    private func presentError(_ error: Error) {
        let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}
