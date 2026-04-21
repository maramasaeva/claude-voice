#!/usr/bin/env swift
// Live microphone listener with wake word + conversation mode
// First utterance needs "claude" wake word. After that, stays in
// conversation mode — always listening. Returns to wake-word mode
// after CONVERSATION_TIMEOUT seconds of silence.
//
// stdout protocol:
//   __WAKE__        — wake word detected, entering conversation mode
//   __LISTENING__   — ready for next message (conversation mode)
//   <text>          — transcribed message
//
// Usage: ./live_listen

import Speech
import AVFoundation
import Foundation

let CONVERSATION_TIMEOUT: TimeInterval = 120  // 2 min silence = back to wake word mode

class VoiceListener: NSObject {
    let audioEngine = AVAudioEngine()
    var recognitionTask: SFSpeechRecognitionTask?
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    var inConversation = false
    var lastActivityTime = Date()

    func start() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                fputs("ERROR: Speech recognition not authorized\n", stderr)
                exit(1)
            }
            DispatchQueue.main.async {
                self.listenForWakeWord()
            }
        }
    }

    // ── Wake word mode ─────────────────────────────────────────

    func listenForWakeWord() {
        stopEngine()
        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        var alreadyTriggered = false

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if alreadyTriggered { return }

            if let result = result {
                let text = result.bestTranscription.formattedString.lowercased()
                if text.contains("claude") || text.contains("cloud") || text.contains("clod") {
                    alreadyTriggered = true
                    self.inConversation = true
                    self.lastActivityTime = Date()
                    print("__WAKE__")
                    fflush(stdout)
                    fputs("WAKE — entering conversation mode\n", stderr)

                    // Check if there's already a message after the wake word
                    var msg = text
                    for wake in ["hey claude", "hi claude", "okay claude", "claude",
                                 "hey cloud", "hi cloud", "okay cloud", "cloud",
                                 "hey clod", "hi clod", "clod"] {
                        if msg.hasPrefix(wake) {
                            msg = String(msg.dropFirst(wake.count))
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .trimmingCharacters(in: CharacterSet(charactersIn: ".,!? "))
                            break
                        }
                    }

                    self.recognitionTask?.cancel()
                    node.removeTap(onBus: 0)
                    self.audioEngine.stop()

                    if !msg.isEmpty && msg.count > 3 {
                        // Message was part of the wake word utterance
                        self.deliverMessage(msg)
                    } else {
                        // Just the wake word, listen for message
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self.listenForMessage()
                        }
                    }
                }
            }

            if let error = error {
                if !alreadyTriggered {
                    fputs("Wake word recognition ended: \(error.localizedDescription). Restarting...\n", stderr)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.listenForWakeWord()
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
            fputs("Audio engine error: \(error). Retrying...\n", stderr)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.listenForWakeWord()
            }
        }
    }

    // ── Message listening (wake word or conversation mode) ────

    func listenForMessage() {
        stopEngine()
        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        var lastText = ""
        var lastChangeTime = Date()
        var delivered = false

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if delivered { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                if text != lastText {
                    lastText = text
                    lastChangeTime = Date()
                }

                if result.isFinal && !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    delivered = true
                    self.deliverMessage(text.trimmingCharacters(in: .whitespaces))
                }
            }

            if let error = error, !delivered {
                if !lastText.trimmingCharacters(in: .whitespaces).isEmpty {
                    delivered = true
                    self.deliverMessage(lastText.trimmingCharacters(in: .whitespaces))
                } else {
                    fputs("Message recognition ended: \(error.localizedDescription)\n", stderr)
                    self.nextListenCycle()
                }
            }
        }

        // Silence timer: if no new text for 2 seconds, deliver what we have
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if delivered { timer.invalidate(); return }

            if !lastText.trimmingCharacters(in: .whitespaces).isEmpty
                && Date().timeIntervalSince(lastChangeTime) > 2.0 {
                timer.invalidate()
                delivered = true
                self.deliverMessage(lastText.trimmingCharacters(in: .whitespaces))
            }

            // If in conversation mode and no speech at all for timeout, go back to wake word
            if self.inConversation && Date().timeIntervalSince(self.lastActivityTime) > CONVERSATION_TIMEOUT {
                timer.invalidate()
                delivered = true
                fputs("Conversation timeout — back to wake word mode\n", stderr)
                self.inConversation = false
                self.recognitionTask?.cancel()
                node.removeTap(onBus: 0)
                self.audioEngine.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.listenForWakeWord()
                }
            }
        }

        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("__LISTENING__")
            fflush(stdout)
            fputs("Listening for message...\n", stderr)
        } catch {
            fputs("Audio engine error: \(error). Retrying...\n", stderr)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.nextListenCycle()
            }
        }
    }

    // ── Deliver and continue ─────────────────────────────────

    func deliverMessage(_ text: String) {
        lastActivityTime = Date()

        // Clean up wake word remnants
        var clean = text.lowercased()
        for wake in ["hey claude", "hi claude", "okay claude", "claude",
                     "hey cloud", "hi cloud", "cloud", "hey clod", "clod"] {
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

        // Continue listening
        stopEngine()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.nextListenCycle()
        }
    }

    func nextListenCycle() {
        if inConversation {
            listenForMessage()
        } else {
            listenForWakeWord()
        }
    }

    func stopEngine() {
        recognitionTask?.cancel()
        recognitionTask = nil
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
    }
}

let listener = VoiceListener()
listener.start()
RunLoop.main.run()
