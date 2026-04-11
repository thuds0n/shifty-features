//
//  PrefAboutViewController.swift
//  Shifty
//
//  Created by Nate Thompson on 11/10/17.
//

import Cocoa
import SwiftUI

// MARK: - PrefAboutView

struct PrefAboutView: View {
    private let integrations = SystemIntegration.shared

    private var appName: String {
        Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "Shifty"
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Identity
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)

                VStack(spacing: 4) {
                    Text(appName)
                        .font(.title2.bold())
                    Text("Version \(versionString)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 44)
            .padding(.bottom, 36)

            // MARK: Actions
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    AboutButton("Check for Updates", systemImage: "arrow.down.circle") {
                        integrations.updater.checkForUpdates(NSNull())
                    }
                    AboutButton("Visit Website", systemImage: "safari") {
                        NSWorkspace.shared.open(URL(string: "https://shifty.natethompson.io")!)
                    }
                }

                HStack(spacing: 10) {
                    AboutButton("Send Feedback", systemImage: "envelope") {
                        NSWorkspace.shared.open(URL(string: "mailto:feedback@natethompson.io?subject=Shifty%20Feedback")!)
                    }
                    AboutButton("Donate", systemImage: "heart") {
                        NSWorkspace.shared.open(URL(string: "https://shifty.natethompson.io/donate")!)
                    }
                }

                HStack(spacing: 10) {
                    AboutButton("Help Translate", systemImage: "character.bubble") {
                        NSWorkspace.shared.open(URL(string: "https://shifty.natethompson.io/translate")!)
                    }
                    AboutButton("Credits", systemImage: "list.bullet.rectangle") {
                        if let path = Bundle.main.path(forResource: "credits", ofType: "rtfd") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                    }
                }
            }
            .padding(.horizontal, 44)

            Spacer()

            Text("© 2017–2026 Nate Thompson · GPLv3 License")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - AboutButton

private struct AboutButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    init(_ label: String, systemImage: String, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .frame(maxWidth: .infinity)
    }
}
