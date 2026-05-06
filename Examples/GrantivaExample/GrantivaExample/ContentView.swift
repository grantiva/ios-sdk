import SwiftUI
import Grantiva

// MARK: - ContentView

struct ContentView: View {
    let grantiva: Grantiva

    @State private var phase: AttestationPhase = .idle
    @State private var result: AttestationResult?
    @State private var flags: [String: FlagValue] = [:]
    @State private var flagsError: String?
    @State private var isLoadingFlags = false

    var body: some View {
        NavigationStack {
            List {
                attestationSection
                if result != nil {
                    deviceSection
                    flagsSection
                }
            }
            .navigationTitle("Grantiva Example")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await attest() }
    }
}

// MARK: - Sections

private extension ContentView {

    var attestationSection: some View {
        Section("Attestation") {
            switch phase {
            case .idle:
                Label("Starting…", systemImage: "clock")
                    .foregroundStyle(.secondary)

            case .loading:
                HStack {
                    ProgressView()
                    Text("Attesting device…")
                        .foregroundStyle(.secondary)
                }

            case .success(let r):
                Label("Attested", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                row("Token", String(r.token.prefix(24)) + "…")
                row("Expires", r.expiresAt.formatted(date: .abbreviated, time: .shortened))
                Button("Re-attest") {
                    grantiva.clearStoredData()
                    Task { await attest() }
                }
                .foregroundStyle(.blue)

            case .simulatorFallback:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Simulator detected", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("App Attest is only available on a real device. Add an API key to test the unattested path (see README).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

            case .failure(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Failed", systemImage: "xmark.shield.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Button("Retry") { Task { await attest() } }
                    .foregroundStyle(.blue)
            }
        }
    }

    var deviceSection: some View {
        Section("Device Intelligence") {
            if let r = result {
                let di = r.deviceIntelligence
                row("Device ID", String(di.deviceId.prefix(12)) + "…")
                row("Risk Category", di.riskCategory.rawValue.capitalized)
                row("Risk Score", di.riskScore.map { "\($0)/100" } ?? "N/A (simulator or Free tier)")
                row("Jailbreak", di.jailbreakDetected ? "Detected" : "Clean")
                row("Integrity", di.deviceIntegrity)
                row("Attestation #", "\(di.attestationCount)")
            }
        }
    }

    var flagsSection: some View {
        Section("Feature Flags") {
            if isLoadingFlags {
                HStack {
                    ProgressView()
                    Text("Fetching flags…").foregroundStyle(.secondary)
                }
            } else if let err = flagsError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if flags.isEmpty {
                Text("No flags configured for this tenant.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(flags.keys.sorted(), id: \.self) { key in
                    if let value = flags[key] {
                        row(key, value.stringValue)
                    }
                }
            }
            Button("Refresh Flags") { Task { await fetchFlags() } }
                .foregroundStyle(.blue)
                .disabled(isLoadingFlags)
        }
    }

    func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }
}

// MARK: - Actions

private extension ContentView {

    func attest() async {
        phase = .loading
        result = nil
        do {
            let r = try await grantiva.validateAttestation()
            result = r
            phase = .success(r)
            await fetchFlags()
        } catch GrantivaError.deviceNotSupported, GrantivaError.attestationNotAvailable {
            // Running on simulator without an apiKey — expected and handled gracefully.
            phase = .simulatorFallback
        } catch {
            phase = .failure(errorMessage(for: error))
        }
    }

    func fetchFlags() async {
        isLoadingFlags = true
        flagsError = nil
        do {
            flags = try await grantiva.flags.getFlags()
        } catch {
            flagsError = errorMessage(for: error)
        }
        isLoadingFlags = false
    }

    func errorMessage(for error: Error) -> String {
        if let ge = error as? GrantivaError {
            return ge.localizedDescription
        }
        return error.localizedDescription
    }
}

// MARK: - Phase

private enum AttestationPhase {
    case idle
    case loading
    case success(AttestationResult)
    case simulatorFallback
    case failure(String)
}

// MARK: - Preview

#Preview {
    // In previews, pass an apiKey so the SDK uses the unattested path.
    ContentView(grantiva: Grantiva(teamId: "YOUR_TEAM_ID", apiKey: "preview-api-key"))
}
