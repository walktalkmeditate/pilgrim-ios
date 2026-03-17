import SwiftUI

struct SettingsView: View {

    @StateObject private var permissionVM = PermissionStatusViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        GeneralSettingsView()
                    } label: {
                        HStack {
                            Text("General")
                                .font(Constants.Typography.body)
                            Spacer()
                            if permissionVM.needsAttention {
                                Circle()
                                    .fill(Color.rust)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        SoundSettingsView()
                    } label: {
                        HStack {
                            Text("Sounds")
                                .font(Constants.Typography.body)
                            Spacer()
                            Text(UserPreferences.soundsEnabled.value ? "On" : "Off")
                                .font(Constants.Typography.caption)
                                .foregroundColor(.fog)
                        }
                    }

                    NavigationLink {
                        TalkSettingsView()
                    } label: {
                        Text("Talks")
                            .font(Constants.Typography.body)
                    }

                    NavigationLink {
                        VoiceGuideSettingsView()
                    } label: {
                        HStack {
                            Text("Voice Guide")
                                .font(Constants.Typography.body)
                            Spacer()
                            Text(UserPreferences.voiceGuideEnabled.value ? "On" : "Off")
                                .font(Constants.Typography.caption)
                                .foregroundColor(.fog)
                        }
                    }
                } header: {
                    Text("Audio")
                        .font(Constants.Typography.caption)
                }

                Section {
                    NavigationLink {
                        FeedbackView()
                    } label: {
                        Text("Leave a Trail Note")
                            .font(Constants.Typography.body)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.parchment)
            .safeAreaInset(edge: .bottom) {
                footer
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                }
            }
            .onAppear { permissionVM.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                permissionVM.refresh()
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog.opacity(0.3))
            Text("crafted with intention")
                .font(Constants.Typography.body.italic())
                .foregroundColor(.fog.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Constants.UI.Padding.breathingRoom)
        .padding(.bottom, Constants.UI.Padding.normal)
        .background(Color.parchment)
    }
}
