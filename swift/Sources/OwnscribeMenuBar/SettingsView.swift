import SwiftUI

struct SettingsAudioForm {
    enum ValidationError: Error, CustomStringConvertible {
        case timeoutNotANonNegativeWholeNumberOfSeconds

        var description: String {
            switch self {
            case .timeoutNotANonNegativeWholeNumberOfSeconds:
                return "Enter the silence timeout as a whole number of seconds (0 disables auto-stop)."
            }
        }
    }

    var micEnabled: Bool
    var silenceTimeoutText: String

    init(loadedFrom url: URL) {
        let settings = OwnscribeConfigWriter.readAudioSettings(from: url)
        micEnabled = settings.mic
        silenceTimeoutText = String(Int(settings.silenceTimeout))
    }

    var validatedSettings: AudioSettings? {
        let trimmed = silenceTimeoutText.trimmingCharacters(in: .whitespaces)
        guard let seconds = Int(trimmed), seconds >= 0 else { return nil }
        return AudioSettings(mic: micEnabled, silenceTimeout: TimeInterval(seconds))
    }

    func save(to url: URL) throws {
        guard let settings = validatedSettings else {
            throw ValidationError.timeoutNotANonNegativeWholeNumberOfSeconds
        }
        try OwnscribeConfigWriter.writeAudioSettings(settings, to: url)
    }
}

struct SettingsView: View {
    private let configURL: URL
    @State private var audioForm: SettingsAudioForm
    @State private var huggingFaceToken: String = ""
    @State private var saveMessage: String?
    @State private var audioMessage: String?
    private let tokenStore = KeychainTokenStore()

    init(configURL: URL = OwnscribeConfigWriter.defaultConfigURL()) {
        self.configURL = configURL
        _audioForm = State(initialValue: SettingsAudioForm(loadedFrom: configURL))
    }

    var body: some View {
        Form {
            Section("Recording") {
                Toggle("Capture my microphone", isOn: $audioForm.micEnabled)
                Text("Off records only what the other participants say.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Auto-stop after silence") {
                    HStack(spacing: 6) {
                        TextField("300", text: $audioForm.silenceTimeoutText)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("0 disables auto-stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Apply") {
                    do {
                        try audioForm.save(to: configURL)
                        audioMessage = "Saved. Restart Clew to apply to the next recording."
                    } catch {
                        audioMessage = String(describing: error)
                    }
                }
                .disabled(audioForm.validatedSettings == nil)

                if let audioMessage {
                    Text(audioMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("HuggingFace token (speaker diarization)") {
                SecureField("hf_...", text: $huggingFaceToken)
                HStack {
                    Button("Save") {
                        let saved = tokenStore.save(huggingFaceToken, for: .huggingFace)
                        saveMessage = saved ? "Saved to Keychain." : "Failed to save."
                    }
                    Button("Remove", role: .destructive) {
                        tokenStore.delete(.huggingFace)
                        huggingFaceToken = ""
                        saveMessage = "Removed."
                    }
                }
                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            huggingFaceToken = tokenStore.load(.huggingFace) ?? ""
            audioForm = SettingsAudioForm(loadedFrom: configURL)
        }
    }
}
