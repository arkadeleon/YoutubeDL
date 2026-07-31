//
//  SettingsView.swift
//  YoutubeDL
//

import SwiftUI

struct SettingsView: View {
    @Binding var isIdleTimerDisabled: Bool

    var body: some View {
        List {
            Toggle("Keep screen turned on", isOn: $isIdleTimerDisabled)
        }
    }
}
