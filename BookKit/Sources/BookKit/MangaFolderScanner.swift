import Foundation

/// Um capítulo: uma pasta que tem imagens dentro.
public struct MangaChapter: Sendable, Equatable {
    public let title: String
    public let pages: [URL]

    public init(title: String, pages: [URL]) {
        self.title = title
        self.pages = pages
    }
}

/// Lê uma pasta e todas as subpastas, juntando as imagens em ordem.
///
/// Regras:
/// - A ordem é a mesma do Finder: "2.jpg" vem antes de "10.jpg".
/// - Em cada pasta, primeiro vêm as imagens dela e depois as subpastas.
/// - Cada pasta com imagens vira um capítulo no sumário.
/// - Pastas "embrulho" (sem imagens e com uma única subpasta) são atravessadas.
/// - Arquivos ocultos, `__MACOSX` e o que não for imagem são ignorados.
public enum MangaFolderScanner {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "tif", "tiff",
    ]

    /// - Parameter title: nome usado para as imagens soltas na pasta principal
    ///   (por padrão, o nome da pasta).
    public static func scan(_ folder: URL, title: String? = nil) throws -> [MangaChapter] {
        // Desce pelas pastas "embrulho", comuns em ZIPs: "Volume 1/Volume 1/Cap 1/...".
        var root = folder
        while true {
            let (images, subfolders) = try contents(of: root)
            guard images.isEmpty, subfolders.count == 1 else { break }
            root = subfolders[0]
        }

        var chapters: [MangaChapter] = []
        try collect(root, title: title ?? folder.lastPathComponent, isRoot: true, into: &chapters)
        return chapters
    }

    private static func collect(_ folder: URL, title: String, isRoot: Bool, into chapters: inout [MangaChapter]) throws {
        let (images, subfolders) = try contents(of: folder)
        if !images.isEmpty {
            chapters.append(MangaChapter(title: title, pages: images))
        }
        for subfolder in subfolders {
            // "Vol 1 › Cap 3" ajuda a diferenciar capítulos com o mesmo nome em volumes diferentes.
            let subtitle = isRoot ? subfolder.lastPathComponent : "\(title) › \(subfolder.lastPathComponent)"
            try collect(subfolder, title: subtitle, isRoot: false, into: &chapters)
        }
    }

    /// Imagens e subpastas de uma pasta, na ordem do Finder.
    private static func contents(of folder: URL) throws -> (images: [URL], subfolders: [URL]) {
        let children = try FileManager.default
            .contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var images: [URL] = []
        var subfolders: [URL] = []
        for url in children {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isFolder {
                if url.lastPathComponent.lowercased() != "__macosx" {
                    subfolders.append(url)
                }
            } else if imageExtensions.contains(url.pathExtension.lowercased()) {
                images.append(url)
            }
        }
        return (images, subfolders)
    }
}
