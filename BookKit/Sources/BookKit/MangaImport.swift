import Foundation

/// Decide o que converter e faz a conversão de cada volume.
///
/// - Cada ZIP, CBZ, RAR, CBR ou 7z vira um volume (um EPUB).
/// - Uma pasta com imagens (em qualquer subpasta) vira um volume.
/// - Uma pasta sem imagens, mas com esses arquivos dentro, vira um volume por arquivo.
public enum MangaImport {
    static let archiveExtensions: Set<String> = ["zip", "cbz", "rar", "cbr", "7z", "cb7"]

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
            try extract(volume, to: temporary) { value in
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

    /// Escolhe o extrator certo olhando os primeiros bytes do arquivo, e não a
    /// extensão (muitos sites mandam ".cbr" que na verdade é ZIP, e vice-versa).
    /// - ZIP: leitor próprio do app.
    /// - RAR: UnRAR oficial.
    /// - Outros (7z...): libarchive do sistema.
    static func extract(_ archive: URL, to destination: URL, progress: (Double) -> Void) throws {
        switch ArchiveKind(of: archive) {
        case .zip:
            try ZipExtractor.extract(archive, to: destination, progress: progress)
        case .rar:
            try RarExtractor.extract(archive, to: destination, progress: progress)
        case .other:
            try ArchiveExtractor.extract(archive, to: destination, progress: progress)
        }
    }

    enum ArchiveKind: Equatable {
        case zip, rar, other

        init(of url: URL) {
            let handle = try? FileHandle(forReadingFrom: url)
            let header = (try? handle?.read(upToCount: 8)) ?? Data()
            try? handle?.close()
            if header.starts(with: [0x50, 0x4B]) {                                  // "PK"
                self = .zip
            } else if header.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]) {   // "Rar!"
                self = .rar
            } else {
                self = .other
            }
        }
    }
}
