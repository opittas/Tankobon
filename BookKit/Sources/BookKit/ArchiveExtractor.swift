import CArchive
import Foundation

/// Extrai as imagens de arquivos RAR, CBR e 7z usando a libarchive do sistema.
///
/// Os arquivos são lidos em sequência, do começo ao fim. Isso funciona até com
/// RAR "sólido", em que um arquivo só pode ser lido depois dos anteriores.
enum ArchiveExtractor {
    enum ExtractError: LocalizedError {
        case cannotOpen(String, String)
        case readFailed(String, String)
        case encrypted(String)
        case oldSolidRar(String)
        case multipart(String)

        var errorDescription: String? {
            switch self {
            case .cannotOpen(let name, let detail):
                "Não consegui abrir “\(name)”. \(detail)"
            case .readFailed(let name, let detail):
                "O arquivo “\(name)” parece estar corrompido, incompleto ou protegido por senha. \(detail)"
            case .encrypted(let name):
                "O arquivo “\(name)” está protegido por senha."
            case .oldSolidRar(let name):
                "“\(name)” foi criado no modo “sólido” do RAR antigo (RAR4), que o iOS não consegue abrir. Extraia no computador e importe a pasta, ou compacte de novo em ZIP."
            case .multipart(let name):
                "“\(name)” é uma parte de um RAR dividido em vários arquivos, que o app ainda não junta. Extraia no computador e importe a pasta."
            }
        }
    }

    /// Extrai as imagens de `archive` para dentro de `destination`, mantendo as pastas.
    static func extract(_ archive: URL, to destination: URL, progress: (Double) -> Void = { _ in }) throws {
        let name = archive.lastPathComponent
        let totalBytes = (try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Double.init) ?? 0

        guard let reader = archive_read_new() else {
            throw ExtractError.cannotOpen(name, "")
        }
        defer { archive_read_free(reader) }

        archive_read_support_filter_all(reader)
        archive_read_support_format_rar(reader)
        archive_read_support_format_rar5(reader)
        archive_read_support_format_7zip(reader)
        archive_read_support_format_zip(reader)

        let openResult = archive.withUnsafeFileSystemRepresentation { path in
            archive_read_open_filename(reader, path, 256 * 1024)
        }
        guard openResult == ARCHIVE_OK else {
            throw ExtractError.cannotOpen(name, errorText(reader))
        }

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var buffer = [UInt8](repeating: 0, count: 256 * 1024)
        var entry: OpaquePointer?

        while true {
            let headerResult = archive_read_next_header(reader, &entry)
            if headerResult == ARCHIVE_EOF { break }
            guard headerResult >= ARCHIVE_WARN, let entry else {
                throw failure(name, reader)
            }

            let entryName = (archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry))
                .map { String(cString: $0) } ?? ""
            let isFile = Int32(archive_entry_filetype(entry)) == CARCHIVE_AE_IFREG

            guard isFile, let relativePath = ZipExtractor.safeImagePath(entryName) else {
                archive_read_data_skip(reader)
                continue
            }
            if archive_entry_is_encrypted(entry) != 0 {
                throw ExtractError.encrypted(name)
            }

            try autoreleasepool {
                let target = destination.appending(path: relativePath)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: target.path(percentEncoded: false), contents: nil)
                let handle = try FileHandle(forWritingTo: target)
                defer { try? handle.close() }

                while true {
                    let count = buffer.withUnsafeMutableBytes { bytes in
                        archive_read_data(reader, bytes.baseAddress, bytes.count)
                    }
                    if count == 0 { break }
                    guard count > 0 else {
                        throw failure(name, reader)
                    }
                    try handle.write(contentsOf: buffer[0..<count])
                }
            }

            if totalBytes > 0 {
                progress(min(1, Double(archive_filter_bytes(reader, -1)) / totalBytes))
            }
        }
        progress(1)
    }

    /// Traduz os erros técnicos da libarchive para mensagens claras.
    private static func failure(_ name: String, _ reader: OpaquePointer) -> ExtractError {
        let detail = errorText(reader)
        if detail.localizedCaseInsensitiveContains("solid") {
            return .oldSolidRar(name)
        }
        if name.range(of: #"\.part\d+\.rar$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return .multipart(name)
        }
        return .readFailed(name, detail)
    }

    private static func errorText(_ reader: OpaquePointer) -> String {
        archive_error_string(reader).map { String(cString: $0) } ?? ""
    }
}
