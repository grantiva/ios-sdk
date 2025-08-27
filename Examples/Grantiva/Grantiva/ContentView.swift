//
//  ContentView.swift
//  Grantiva
//
//  Created by Kyle Browning on 7/23/25.
//

import SwiftUI
import Grantiva

struct ContentView: View {
    @State private var grantiva = Grantiva(teamId: "ABBM6U9RM5")
    @State private var attestationResult: AttestationResult?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var currentToken: String?
    @State private var isTokenValid = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Status Card
                    statusCard
                    
                    // Action Buttons
                    actionButtons
                    
                    // Token Information
                    if let token = currentToken {
                        tokenCard(token: token)
                    }
                    
                    // Attestation Result
                    if let result = attestationResult {
                        attestationResultCard(result: result)
                    }
                    
                    // Error Display
                    if let error = errorMessage {
                        errorCard(error: error)
                    }
                }
                .padding()
            }
            .navigationTitle("Grantiva SDK Test")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            checkCurrentToken()
        }
    }
    
    // MARK: - View Components
    
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("SDK Status", systemImage: "checkmark.shield")
                .font(.headline)
            
            HStack {
                Text("Token Status:")
                    .foregroundColor(.secondary)
                Text(isTokenValid ? "Valid" : "Invalid/None")
                    .foregroundColor(isTokenValid ? .green : .red)
                    .fontWeight(.medium)
            }
            
            if let result = attestationResult {
                HStack {
                    Text("Expires:")
                    Text(result.expiresAt, style: .relative)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: performAttestation) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "shield.checkered")
                    }
                    Text("Validate Attestation")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isLoading)
            
            Button(action: refreshToken) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh Token")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isTokenValid ? Color.green : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(!isTokenValid || isLoading)
            
            Button(action: checkCurrentToken) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Check Token Status")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            
            Button(action: clearStoredData) {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear Stored Data (Testing)")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
    }
    
    private func tokenCard(token: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Current Token", systemImage: "key.fill")
                .font(.headline)
            
            Text(String(token.prefix(20)) + "...")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))
                .cornerRadius(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func attestationResultCard(result: AttestationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Device Intelligence", systemImage: "cpu")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Device ID", value: String(result.deviceIntelligence.deviceId.prefix(12)) + "...")
                InfoRow(label: "Risk Score", value: "\(result.deviceIntelligence.riskScore)/100")
                InfoRow(label: "Device Integrity", value: result.deviceIntelligence.deviceIntegrity)
                InfoRow(label: "Jailbreak Detected", value: result.deviceIntelligence.jailbreakDetected ? "Yes" : "No")
                InfoRow(label: "Attestation Count", value: "\(result.deviceIntelligence.attestationCount)")
                
                if let lastDate = result.deviceIntelligence.lastAttestationDate {
                    InfoRow(label: "Last Attestation", value: lastDate.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func errorCard(error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(error)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - Actions
    
    private func performAttestation() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await grantiva.validateAttestation()
                await MainActor.run {
                    self.attestationResult = result
                    self.currentToken = result.token
                    self.isTokenValid = true
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func refreshToken() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                if let result = try await grantiva.refreshToken() {
                    await MainActor.run {
                        self.attestationResult = result
                        self.currentToken = result.token
                        self.isTokenValid = true
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func checkCurrentToken() {
        currentToken = grantiva.getCurrentToken()
        isTokenValid = grantiva.isTokenValid()
    }
    
    private func clearStoredData() {
        grantiva.clearStoredData()
        attestationResult = nil
        currentToken = nil
        isTokenValid = false
        errorMessage = nil
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    ContentView()
}
