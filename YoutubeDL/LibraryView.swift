//
//  LibraryView.swift
//  YoutubeDL
//

import QuickLook
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var app: AppModel

    @State private var sharedFile: DownloadedFile?
    @State private var errorMessage = ""
    @State private var isShowingError = false

    var body: some View {
        List(app.downloads) { file in
            NavigationLink {
                FilePreviewView(url: file.url)
                    .navigationTitle(file.name)
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                FileRow(file: file)
            }
            .contextMenu {
                Button("Share", systemImage: "square.and.arrow.up") {
                    share(file)
                }

                Button("Delete", systemImage: "trash", role: .destructive) {
                    delete(file)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    delete(file)
                }

                Button("Share", systemImage: "square.and.arrow.up") {
                    share(file)
                }
                .tint(.blue)
            }
        }
        .overlay {
            if app.downloads.isEmpty {
                Label("No Files", systemImage: "photo.fill.on.rectangle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            refresh()
        }
        .refreshable {
            refresh()
        }
        .sheet(item: $sharedFile) { file in
            ShareSheet(items: [file.url])
        }
        .alert("Unable to Update Files", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func refresh() {
        do {
            try app.refreshDownloads()
        } catch {
            present(error)
        }
    }

    private func share(_ file: DownloadedFile) {
        sharedFile = file
    }

    private func delete(_ file: DownloadedFile) {
        do {
            try app.delete(file)
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }
}

private struct FileRow: View {
    var file: DownloadedFile

    @EnvironmentObject private var app: AppModel
    @Environment(\.displayScale) private var displayScale

    @ScaledMetric(relativeTo: .body) private var thumbnailSize = 56

    @State private var thumbnail: UIImage?
    @State private var duration: String?

    var body: some View {
        HStack {
            ZStack {
                Color.secondary.opacity(0.15)

                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: file.iconName)
                        .resizable()
                        .scaledToFit()
                        .padding()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: thumbnailSize, height: thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading) {
                Text(file.name)
                    .lineLimit(2)

                HStack {
                    Text(file.byteCount, format: .byteCount(style: .file))

                    if let duration {
                        Text(duration)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .task(id: file.id) {
            await loadThumbnail()
        }
        .task(id: file.id) {
            await loadDuration()
        }
    }

    private func loadThumbnail() async {
        let image = await app.loadThumbnail(
            for: file,
            size: CGSize(width: thumbnailSize, height: thumbnailSize),
            scale: displayScale
        )
        guard !Task.isCancelled else {
            return
        }
        thumbnail = image
    }

    private func loadDuration() async {
        let value = await app.loadDuration(for: file)
        guard !Task.isCancelled else {
            return
        }
        duration = value
    }
}

private struct FilePreviewView: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        controller.reloadData()
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
    }
}
