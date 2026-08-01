//
//  MainView.swift
//
//  Copyright (c) 2020 Changbeom Ahn
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
import SwiftUI

struct MainView: View {
    @AppStorage("isIdleTimerDisabled") private var isIdleTimerDisabled = false

    var body: some View {
        TabView {
            NavigationView {
                DownloadView()
                    .navigationTitle("Download")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Download", systemImage: "arrow.down.circle")
            }

            NavigationView {
                DownloadsView()
                    .navigationTitle("Downloads")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Downloads", systemImage: "folder.circle")
            }

            NavigationView {
                SettingsView(isIdleTimerDisabled: $isIdleTimerDisabled)
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Settings", systemImage: "gear.circle")
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = isIdleTimerDisabled
        }
        .onChange(of: isIdleTimerDisabled) { newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
    }
}

struct DownloadView: View {
    @State private var alertMessage: String?

    @State private var isShowingAlert = false

    @State private var error: Error? {
        didSet {
            guard error != nil else { return }
            alertMessage = error?.localizedDescription
            isShowingAlert = true
        }
    }

    @EnvironmentObject private var app: AppModel

    @State private var urlString = ""

    var body: some View {
        List {
            Section {
                TextField("Enter URL", text: $urlString)
                    .onSubmit(submitURL)

                Button("Paste URL", action: pasteURL)
            }

            if app.showProgress {
                ProgressView(app.progress)
            }
        }
        .onChange(of: app.url) { newValue in
            guard let url = newValue else { return }
            urlString = url.absoluteString
        }
        .onReceive(app.$error) {
            error = $0
        }
        .onReceive(app.$exception) {
            alertMessage = $0?.description
            isShowingAlert = alertMessage != nil
        }
        .alert(isPresented: $isShowingAlert) {
            Alert(title: Text(alertMessage ?? "no message?"))
        }
    }

    private func pasteURL() {
        let pasteBoard = UIPasteboard.general
        guard let url = pasteBoard.url ?? pasteBoard.string.flatMap(URL.init(string:)) else {
            alert(message: "Nothing to paste")
            return
        }
        urlString = url.absoluteString
        app.url = url
    }

    private func submitURL() {
        guard let url = URL(string: urlString) else {
            alert(message: "Invalid URL")
            return
        }
        app.url = url
    }

    private func alert(message: String) {
        alertMessage = message
        isShowingAlert = true
    }
}
