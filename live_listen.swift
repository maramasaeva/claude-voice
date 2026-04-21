#!/usr/bin/env swift
// Live microphone listener with wake word detection using macOS Speech Recognition
// Outputs transcribed text to stdout, one line per utterance
// Usage: swift live_listen.swift

import Speech
import AVFoundation
import Foundation

class VoiceListener: NSObject {
    let audioEngine = AVAudioEngine()
    var recognitionTask: SFSpeechRecognitionTask?
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    var isListeningForMessage = false
    var messageBuffer = ""
    var silenceTimer: Timer?

    func start() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                fputs("ERROR: Speech recognition not authorized\n", stderr)
                exit(1)
            }
            DispatchQueue.main.async {
                self.startListening()
            }
        }
    }

    func startListening() {
        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            guard let result = result else {
                if let error = error {
                    fputs("Recognition error: \(error.localizedDescription)\n", stderr)
                }
                return
            }

            let text = result.bestTranscription.formattedString.lowercased()

            if !self.isListeningForMessage {
                // Check for wake word
                if text.contains("claude") || text.contains("hey cloud") || text.contains("hey clod") {
                    fputs("WAKE\n", stderr)
                    print("__WAKE__", terminator: "\n")
                    fflush(stdout)
                    self.isListeningForMessage = true
                    self.messageBuffer = ""

                    // Restart recognition to get clean message
                    self.recognitionTask?.cancel()
                    node.removeTap(onBus: 0)
                    self.audioEngine.stop()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.startMessageListening()
                    }
                }
            }
        }

        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            fputs("Listening for wake word...\n", stderr)
        } catch {
            fputs("Audio engine error: \(error)\n", stderr)
            exit(1)
        }
    }

    func startMessageListening() {
        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        var lastText = ""
        var lastChangeTime = Date()

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                if text != lastText {
                    lastText = text
                    lastChangeTime = Date()
                    self.messageBuffer = text
                }

                // Check if final or if text hasn't changed for 2 seconds
                if result.isFinal {
                    self.deliverMessage()
                }
            } else if let error = error {
                // Recognition ended
                self.deliverMessage()
            }
        }

        // Timer to check for silence (no new transcription for 2 seconds)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if !self.isListeningForMessage {
                timer.invalidate()
                return
            }
            if !self.messageBuffer.isEmpty && Date().timeIntervalSince(lastChangeTime) > 2.0 {
                timer.invalidate()
                self.deliverMessage()
            }
        }

        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            fputs("Listening for message...\n", stderr)
        } catch {
            fputs("Audio engine error: \(error)\n", stderr)
        }
    }

    func deliverMessage() {
        guard isListeningForMessage else { return }
        isListeningForMessage = false

        let msg = messageBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !msg.isEmpty {
            // Remove wake word from beginning
            var clean = msg.lowercased()
            for wake in ["hey claude", "hi claude", "okay claude", "claude"] {
                if clean.hasPrefix(wake) {
                    clean = String(clean.dropFirst(wake.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: ".,!? "))
                    break
                }
            }
            if !clean.isEmpty {
                print(clean)
                fflush(stdout)
                fputs("Sent: \(clean)\n", stderr)
            }
        }

        // Stop and restart for next wake word
        recognitionTask?.cancel()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        messageBuffer = ""

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startListening()
        }
    }
}

let listener = VoiceListener()
listener.start()
RunLoop.main.run()
