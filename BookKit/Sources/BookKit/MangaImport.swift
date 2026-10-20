import Foundation

/// Decide o que converter e faz a conversão de cada volume.
///
/// - Cada ZIP/CBZ vira um volume (um EPUB).
/// - Uma pasta com imagens (em qualquer subpasta) vira um volume.
/// - Uma pasta sem imagens, mas com ZIPs/CBZs dentro, vira um volume por arquivo.
public enum MangaImport {
    static let archiveExtensions: Set<String> = ["zip", "cbz"]

    public static func isArchive(_ url: URL) -> Bool {
        archiveExtensions.contains(url.pathExtension.lowercased())
    }

    /// Lista os volumes a converter, em ordem.
    public static func volumes(in selection: [URL]) throws -> [URL] {
        var volumes: [URL] = []
        for url in selection {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isFolder {
                if try MangaFolderScanner.scan(url).isEmpty {
                    let archives = try FileManager.default
                        .contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                        .filter(isArchive)
                        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                    volumes += archives
                } else {
                    volumes.append(url)
                }
            } else if isArchive(url) {
                volumes.append(url)
            }
        }
        return volumes
    }

    /// Nome do livro: o nome do arquivo (sem ".zip") ou o nome da pasta.
    public static func title(of volume: URL) -> String {
        isArchive(volume) ? volume.deletingPathExtension().lastPathComponent : volume.lastPathComponent
    }

    /// Converte um volume em EPUB dentro da biblioteca e devolve o caminho do livro criado.
    @discardableResult
    public static func convert(
        _ volume: URL,
        into store: LibraryStore,
        progress: @Sendable (Double) -> Void = { _ in }
    ) throws -> URL {
        let title = title(of: volume)
        let isZip = isArchive(volume)
        var folder = volume
        var temporaryFolder: URL?
        defer {
            // A pasta temporária com as imagens extraídas é sempre apagada no fim.
            if let temporaryFolder {
                try? FileManager.default.removeItem(at: temporaryFolder)
            }
        }

        if isZip {
            let temporary = FileManager.default.temporaryDirectory.appending(path: "Tankobon-\(UUID().uuidString)")
            temporaryFolder = temporary
            try ZipExtractor.extract(volume, to: temporary) { value in
                progress(value * 0.3)
            }
            folder = temporary
        }

        let chapters = try MangaFolderScanner.scan(folder, title: title)
        let output = try store.reserveDestination(fileName: "\(title).epub")
        try MangaEPUBBuilder(rightToLeft: true).build(chapters: chapters, title: title, to: output) { value in
            progress(isZip ? 0.3 + value * 0.7 : value)
        }
        return output
    }
}
