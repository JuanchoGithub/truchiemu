import SwiftUI

// MARK: - RetroAchievements Settings View
struct RetroAchievementsSettingsView: View {
    @ObservedObject private var raService = RetroAchievementsService.shared
    @State private var username = ""
    @State private var password = ""
    @State private var loginError: String?
    @State private var isLoggingIn = false
    @State private var showPassword = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Enable/Disable Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("RetroAchievements", systemImage: "trophy.fill")
                            .font(.headline)
                        Spacer()
                        Toggle("Enable", isOn: Binding(
                            get: { raService.isEnabled },
                            set: { raService.setEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                    }
                    
                    if !raService.isEnabled {
                        Text("Enable RetroAchievements to track your achievements and compete on leaderboards.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                
                // Account Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Account", systemImage: "person.badge.key")
                            .font(.headline)
                        Spacer()
                        if raService.isLoggedIn {
                            HStack(spacing: 4) {
                                Circle().fill(.green).frame(width: 8, height: 8)
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Circle().fill(.secondary).frame(width: 8, height: 8)
                                Text("Not Connected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if raService.isLoggedIn {
                        // Logged in state
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.purple)
                                VStack(alignment: .leading) {
                                    Text(raService.username ?? "Unknown")
                                        .font(.headline)
                                    if let userInfo = raService.userInfo {
                                        Text("Rank: #\(userInfo.rank) • \(userInfo.totalPoints) points")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Logout") {
                                    raService.saveSettings(username: "", token: "")
                                    raService.isLoggedIn = false
                                    raService.userInfo = nil
                                    username = ""
                                    password = ""
                                }
                                .buttonStyle(.bordered)
                                .tint(.red.opacity(0.8))
                            }
                            
                            if let userInfo = raService.userInfo {
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Total Points:")
                                        Spacer()
                                        Text("\(userInfo.totalPoints)")
                                            .fontWeight(.semibold)
                                    }
                                    HStack {
                                        Text("Hardcore Points:")
                                        Spacer()
                                        Text("\(userInfo.totalHardcorePoints)")
                                            .fontWeight(.semibold)
                                    }
                                    HStack {
                                        Text("TruePoints:")
                                        Spacer()
                                        Text("\(userInfo.totalTruePoints)")
                                            .fontWeight(.semibold)
                                    }
                                    HStack {
                                        Text("Member Since:")
                                        Spacer()
                                        Text(userInfo.memberSince)
                                    }
                                }
                                .font(.caption)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    } else {
                        // Login form
                        VStack(spacing: 12) {
                            TextField("Username", text: $username)
                                .textFieldStyle(.roundedBorder)
                                .disableAutocorrection(true)
                            
                            HStack {
                                if showPassword {
                                    TextField("Password", text: $password)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    SecureField("Password", text: $password)
                                        .textFieldStyle(.roundedBorder)
                                }
                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if let error = loginError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            
                            Button(action: login) {
                                if isLoggingIn {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Login")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isLoggingIn || username.isEmpty || password.isEmpty)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        
                        Text("Enter your RetroAchievements credentials. Your password is only used to obtain an API token and is never stored.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 4) {
                            Text("Don't have an account?")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Link("Register on RetroAchievements", destination: URL(string: "https://retroachievements.org/createaccount.php")!)
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                
                // Hardcore Mode Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Hardcore Mode", systemImage: "shield.lefthalf.filled")
                            .font(.headline)
                        Spacer()
                        Toggle("Enabled", isOn: Binding(
                            get: { raService.hardcoreMode },
                            set: { raService.setHardcoreMode($0) }
                        ))
                        .toggleStyle(.switch)
                        .disabled(!raService.isEnabled)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hardcore Mode enforces stricter rules for achievements:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            hardcoreRule("Save States are disabled")
                            hardcoreRule("Rewind is disabled")
                            hardcoreRule("Slow Motion is disabled")
                            hardcoreRule("Cheat codes are disabled")
                        }
                        
                        Text("Using any of these features will drop your session to Softcore mode.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 4)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                
                // Rich Presence Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Rich Presence", systemImage: "text.bubble.fill")
                            .font(.headline)
                    }
                    
                    if let richPresence = raService.richPresence {
                        Text(richPresence)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.secondary.opacity(0.1))
                            .cornerRadius(8)
                    } else {
                        Text("No game currently active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                
                // Info Section
                VStack(alignment: .leading, spacing: 8) {
                    Label("About RetroAchievements", systemImage: "info.circle")
                        .font(.headline)
                    
                    Text("RetroAchievements adds achievements to classic games. Earn trophies, compete on leaderboards, and track your progress across thousands of retro games.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Link("Visit retroachievements.org", destination: URL(string: "https://retroachievements.org")!)
                        .font(.caption)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("RetroAchievements")
    }
    
    private func hardcoreRule(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red.opacity(0.7))
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func login() {
        isLoggingIn = true
        loginError = nil
        
        Task {
            do {
                _ = try await raService.login(username: username, password: password)
                await MainActor.run {
                    isLoggingIn = false
                    password = "" // Clear password after login
                }
            } catch {
                await MainActor.run {
                    isLoggingIn = false
                    loginError = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    RetroAchievementsSettingsView()
}