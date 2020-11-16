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
    let tickFile: AVAudioFile = {
        let tickURL = Bundle.main.url(forResource: "tick", withExtension: "mp3")!
        return try! AVAudioFile(forReading: tickURL)
    }()

    var engine = AVAudioEngine()
    var sourceNode: AVAudioSourceNode!
    var sourceMixerNode = AVAudioMixerNode()
    var sinkNode: AVAudioSinkNode!
    var metronomePlayerNode = AVAudioPlayerNode()
    var metronomeMixerNode = AVAudioMixerNode()
    var recordingPlayerNode = AVAudioPlayerNode()
    var recordingMixerNode = AVAudioMixerNode()
    var recordingBuffer: AVAudioPCMBuffer!
    @Synchronized var isRecording = false
    @Synchronized var frequency = 100.0
    @Synchronized var bpm = 60.0
    var metronomeBase: AVAudioFramePosition = 0

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord)
            try session.setMode(.default)
            try session.setPreferredInputNumberOfChannels(1)
            try session.setActive(true)
        } catch {
            presentError(error)
        }
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
        sourceMixerNode.outputVolume = sineWaveSwitch.isOn ? sineWaveVolumeSlider.value : 0.0
    }

    @IBAction func bpmSliderTouchUpInside(_ sender: UISlider) {
        setBPM()
    }

    private func setBPM() {
        bpm = Double(bpmSlider.value)
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
        metronomeMixerNode.outputVolume = metronomeSwitch.isOn ? metronomeVolumeSlider.value : 0.0
    }

    @IBAction func recordTapped(_ sender: Any) {
        isRecording.toggle()
        let isRecording = self.isRecording
        playButton.isEnabled = !isRecording
        let recordButtonTitle = isRecording ? "Stop Recording" : "Start Recording"
        recordButton.setTitle(recordButtonTitle, for: .normal)
        if isRecording { recordingBuffer.frameLength = 0 }
    }

    @IBAction func playTapped(_ sender: Any) {
        recordingPlayerNode.scheduleBuffer(recordingBuffer) {
            print("Finished playing recording")
        }
    }

    private func getRecordPermissionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        let micPermission = session.recordPermission
        if micPermission == .granted {
            startEngine()
        } else {
            session.requestRecordPermission { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.startEngine() }
            }
        }
    }

    private func configureEngine() {
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        setupSourceNode()
        setupSinkNode(inputFormat: inputFormat)
        engine.attach(sourceNode)
        engine.attach(sourceMixerNode)
        engine.attach(sinkNode)
        engine.attach(metronomePlayerNode)
        engine.attach(metronomeMixerNode)
        engine.attach(recordingPlayerNode)
        engine.attach(recordingMixerNode)
        engine.connect(sourceNode, to: sourceMixerNode, format: standardFormat)
        engine.connect(sourceMixerNode, to: engine.mainMixerNode, format: nil)
        engine.connect(metronomePlayerNode, to: metronomeMixerNode, format: nil)
        engine.connect(metronomeMixerNode, to: engine.mainMixerNode, format: nil)
        engine.connect(recordingPlayerNode, to: recordingMixerNode, format: recordingBuffer.format)
        engine.connect(recordingMixerNode, to: engine.mainMixerNode, format: nil)
        engine.connect(engine.inputNode, to: sinkNode, format: inputFormat)
        setFrequency()
        setBPM()
        setSinewaveVolume()
        setMetronomeVolume()
    }

    private func startEngine() {
        configureEngine()
        do {
            try engine.start()
            startMetronomePlayer()
            startRecordingPlayer()
        } catch {
            presentError(error)
        }
    }

    private func setupSourceNode() {
        sourceNode = AVAudioSourceNode(format: standardFormat, renderBlock: { (_, timeStamp, frameCount, audioBufferList) -> OSStatus in
            for frame in 0..<Int(frameCount) {
                let absoluteFrame = timeStamp.pointee.mSampleTime + Double(frame)
                let time = absoluteFrame / Double(self.standardFormat.sampleRate)
                let sample = sin(2.0 * .pi * self.frequency * time)
                let listPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
                for buffer in listPointer {
                    let bufferPointer = UnsafeMutableBufferPointer<Float>(buffer)
                    bufferPointer[frame] = Float(sample)
                }
            }
            return OSStatus(0)
        })
    }

    private func setupSinkNode(inputFormat: AVAudioFormat) {
        recordingBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(inputFormat.sampleRate * 30))!
        recordingBuffer.frameLength = 0
        sinkNode = AVAudioSinkNode(receiverBlock: { [weak self] (_, audioFrameCount, audioBufferList) -> OSStatus in
            guard let self = self, self.isRecording else { return 0 }
            withUnsafePointer(to: self.recordingBuffer.audioBufferList.pointee.mBuffers) { recordingAudioBufferArrayPtr in
                withUnsafePointer(to: audioBufferList.pointee.mBuffers) { sourceAudioBufferArrayPtr in
                    for i in 0..<1 {
                        let recordingAudioBuffer = (recordingAudioBufferArrayPtr + i)
                        let sourceAudioBuffer = (sourceAudioBufferArrayPtr + i)
                        recordingAudioBuffer.pointee.mData!.advanced(by: Int(recordingAudioBuffer.pointee.mDataByteSize)).copyMemory(from: sourceAudioBuffer.pointee.mData!, byteCount: Int(sourceAudioBuffer.pointee.mDataByteSize))
                    }
                }
            }
            self.recordingBuffer.frameLength += audioFrameCount
            return 0  // no error
        })
    }

    private func startMetronomePlayer() {
        metronomeBase = 0
        let startTime = AVAudioTime(sampleTime: 0, atRate: tickFile.fileFormat.sampleRate)
        self.metronomePlayerNode.scheduleFile(tickFile, at: startTime) { [weak self] in
            self?.rescheduleMetronome()
        }
        if engine.isRunning { metronomePlayerNode.play() }
    }

    private func startRecordingPlayer() {
        recordingPlayerNode.play()
    }

    private func rescheduleMetronome() {
        guard let renderTime = self.metronomePlayerNode.lastRenderTime, let playerTime = self.metronomePlayerNode.playerTime(forNodeTime: renderTime), playerTime.isSampleTimeValid else { return }
        let framesPerSecond = AVAudioFramePosition(tickFile.fileFormat.sampleRate)
        metronomeBase += 60 * framesPerSecond / AVAudioFramePosition(bpm)
        let startTime = AVAudioTime(sampleTime: metronomeBase, atRate: tickFile.fileFormat.sampleRate)
        self.metronomePlayerNode.scheduleFile(tickFile, at: startTime) { [weak self] in
            self?.rescheduleMetronome()
        }
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}
