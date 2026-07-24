import SwiftUI

struct SettingsView: View {
    @State private var huggingFaceToken: String = ""
    @State private var saveMessage: String?
    private let tokenStore = KeychainTokenStore()

    var body: some View {
        Form {
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
        }
    }
}
