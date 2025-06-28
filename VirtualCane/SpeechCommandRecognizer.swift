//
//  SpeechCommandRecognizer.swift
//  *Left here for future development, currently not used in the project*
//  VirtualCane
//

import Foundation
import Combine
import Speech
import AVFoundation

enum SpeechCommand { case start, stop }

final class SpeechCommandRecognizer: NSObject, ObservableObject {

    @Published var command: SpeechCommand?

    private let recognizer      = SFSpeechRecognizer(locale: .current)
    private let audioEngine     = AVAudioEngine()
    private var request         : SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask : SFSpeechRecognitionTask?
    private var sessionPrepared = false

    // MARK: – Life-cycle
    override init() {
        super.init()
        requestAuthorisation()
    }

    deinit { stopRecognition(terminateSession: true) }
}

// MARK: – Authorisation
private extension SpeechCommandRecognizer {

    func requestAuthorisation() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                print("Speech-recognition denied:", status.rawValue); return
            }
            DispatchQueue.main.async { self?.startRecognition() }
        }
    }
}

// MARK: – Recognition + audio session
private extension SpeechCommandRecognizer {

    func prepareAudioSession() throws {
        guard !sessionPrepared else { return }
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(.playAndRecord,
                                mode: .spokenAudio,
                                options: [.defaultToSpeaker,
                                          .mixWithOthers,
                                          .allowBluetoothA2DP])
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        sessionPrepared = true
    }

    func startRecognition() {
        do { try prepareAudioSession() } catch {
            print("Audio-session error:", error); return
        }

        stopRecognition(terminateSession: false)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .confirmation
        request = req

        // Mic tap
        let input  = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            self?.request?.append(buf)
        }

        do {
            audioEngine.prepare(); try audioEngine.start()
        } catch { print("AudioEngine error:", error); return }

        recognitionTask = recognizer?.recognitionTask(with: req) { [weak self] res, err in
            guard let self else { return }
            if let t = res?.bestTranscription.formattedString { self.handle(transcript: t) }
            if err != nil || (res?.isFinal ?? false) { self.startRecognition() }
        }
    }

    func stopRecognition(terminateSession: Bool) {
        recognitionTask?.cancel(); recognitionTask = nil
        request?.endAudio();           request = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        if terminateSession {
            try? AVAudioSession.sharedInstance()
                  .setActive(false, options: .notifyOthersOnDeactivation)
            sessionPrepared = false
        }
    }
}

// MARK: – Keyword spotting
private extension SpeechCommandRecognizer {

    func handle(transcript: String) {
        let lower = transcript.lowercased()
        if lower.contains("start") { command = .start }
        else if lower.contains("stop") { command = .stop }
    }
}
