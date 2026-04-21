#!/usr/bin/env swift
// Transcribe a WAV file using macOS on-device speech recognition
// Usage: swift transcribe_macos.swift /path/to/audio.wav

import Speech
import Foundation

guard CommandLine.arguments.count > 1 else {
    print("Usage: transcribe_macos.swift <audio_file>")
    exit(1)
}

let filePath = CommandLine.arguments[1]
let fileURL = URL(fileURLWithPath: filePath)

let semaphore = DispatchSemaphore(value: 0)

SFSpeechRecognizer.requestAuthorization { status in
    guard status == .authorized else {
        print("ERROR:Speech recognition not authorized (status: \(status.rawValue))")
        semaphore.signal()
        return
    }

    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
        print("ERROR:Could not create recognizer")
        semaphore.signal()
        return
    }

    let request = SFSpeechURLRecognitionRequest(url: fileURL)
    request.shouldReportPartialResults = false
    request.requiresOnDeviceRecognition = true

    recognizer.recognitionTask(with: request) { result, error in
        if let result = result, result.isFinal {
            print(result.bestTranscription.formattedString)
        } else if let error = error {
            print("ERROR:\(error.localizedDescription)")
        }
        semaphore.signal()
    }
}

semaphore.wait()
