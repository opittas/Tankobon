import Foundation

/// Um arquivo guardado na biblioteca do app.
public struct BookItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let format: BookFormat
    public let fileSize: Int64
    public let addedAt: Date

    public var id: URL { url }

    /// Nome do arquivo sem a extensão.
    public var title: String {
        url.deletingPathExtension().lastPathComponent
    }
}

public enum LibraryError: LocalizedError, Equatable {
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            "O formato .\(ext) não é suportado."
        }
    }
}

/// Guarda os arquivos importados numa pasta dentro do app.
/// A lista da biblioteca é simplesmente o conteúdo dessa pasta.
public struct LibraryStore: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// Pasta padrão: Documentos/Biblioteca, dentro do app.
    public static var standard: LibraryStore {
        LibraryStore(folder: URL.documentsDirectory.appending(path: "Biblioteca", directoryHint: .isDirectory))
    }

    /// Todos os arquivos da biblioteca, do mais recente para o mais antigo.
    public func items() throws -> [BookItem] {
        try createFolderIfNeeded()
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return urls
            .compactMap(makeItem)
            .sorted { $0.addedAt > $1.addedAt }
    }

    /// Copia um arquivo para dentro da biblioteca.
    /// Se já existir um arquivo com o mesmo nome, adiciona " (2)", " (3)"...
    @discardableResult
    public func importFile(from source: URL) throws -> BookItem {
        guard BookFormat(url: source) != nil else {
            throw LibraryError.unsupportedFormat(source.pathExtension.lowercased())
        }
        try createFolderIfNeeded()
        let destination = uniqueDestination(for: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        // A cópia mantém a data do arquivo original; marcamos a data da importação.
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path(percentEncoded: false))
        guard let item = makeItem(destination) else {
            throw LibraryError.unsupportedFormat(source.pathExtension.lowercased())
        }
        return item
    }

    /// Reserva um caminho livre dentro da biblioteca para um arquivo novo
    /// (usado pela conversão, que grava o EPUB direto aqui, sem cópia extra).
    public func reserveDestination(fileName: String) throws -> URL {
        try createFolderIfNeeded()
        return uniqueDestination(for: fileName)
    }

    /// Apaga um arquivo da biblioteca.
    public func delete(_ item: BookItem) throws {
        try FileManager.default.removeItem(at: item.url)
    }

    // MARK: - Auxiliares

    private func createFolderIfNeeded() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func makeItem(_ url: URL) -> BookItem? {
        guard let format = BookFormat(url: url) else { return nil }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return BookItem(
            url: url,
            format: format,
            fileSize: Int64(values?.fileSize ?? 0),
            addedAt: values?.contentModificationDate ?? .distantPast
        )
    }

    func uniqueDestination(for fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = folder.appending(path: fileName)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = folder.appending(path: "\(base) (\(number)).\(ext)")
            number += 1
        }
        return candidate
    }
}
