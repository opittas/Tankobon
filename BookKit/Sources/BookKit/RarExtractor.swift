import CUnrar
import Foundation

/// Extrai as imagens de arquivos RAR e CBR usando o UnRAR oficial.
///
/// Abre RAR4 e RAR5, inclusive no modo "sólido". Os arquivos são lidos em
/// sequência; os que não são imagens são pulados sem gravar nada.
enum RarExtractor {
    enum ExtractError: LocalizedError {
        case notARar(String)
        case damaged(String)
        case encrypted(String)
        case multipart(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .notARar(let name):
                "“\(name)” não é um arquivo RAR válido."
            case .damaged(let name):
                "O arquivo “\(name)” parece estar corrompido ou incompleto. Tente baixá-lo de novo."
            case .encrypted(let name):
                "O arquivo “\(name)” está protegido por senha."
            case .multipart(let name):
                "“\(name)” é uma parte de um RAR dividido em vários arquivos (.part1, .part2...), que o app ainda não junta. Extraia no computador e importe a pasta."
            case .writeFailed(let name):
                "Não consegui gravar as imagens de “\(name)”. Verifique se há espaço livre no aparelho."
            }
        }
    }

    /// Recebe os pedaços descompactados e grava no arquivo de destino.
    private final class Sink {
        let handle: FileHandle
        var failed = false

        init(handle: FileHandle) {
            self.handle = handle
        }
    }

    static func extract(_ archive: URL, to destination: URL, progress: (Double) -> Void = { _ in }) throws {
        let name = archive.lastPathComponent
        var openResult: Int32 = 0
        let rar = archive.withUnsafeFileSystemRepresentation { path in
            tankobon_rar_open(path, &openResult)
        }
        guard let rar else {
            throw error(for: openResult, name: name)
        }
        defer { tankobon_rar_close(rar) }

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let totalBytes = Double((try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        var writtenBytes = 0.0
        var nameBuffer = [CChar](repeating: 0, count: 4096)
        var isDirectory: Int32 = 0
        var isEncrypted: Int32 = 0

        while true {
            let next = tankobon_rar_next(rar, &nameBuffer, Int32(nameBuffer.count), &isDirectory, &isEncrypted)
            if next == TANKOBON_RAR_END { break }
            guard next == TANKOBON_RAR_OK else { throw error(for: next, name: name) }

            let entryName = String(cString: nameBuffer)
            guard isDirectory == 0, let relativePath = ZipExtractor.safeImagePath(entryName) else {
                let skip = tankobon_rar_skip(rar)
                guard skip == TANKOBON_RAR_OK else { throw error(for: skip, name: name) }
                continue
            }
            if isEncrypted != 0 { throw ExtractError.encrypted(name) }

            try autoreleasepool {
                let target = destination.appending(path: relativePath)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: target.path(percentEncoded: false), contents: nil)
                let sink = Sink(handle: try FileHandle(forWritingTo: target))
                defer { try? sink.handle.close() }

                let context = Unmanaged.passUnretained(sink).toOpaque()
                let result = tankobon_rar_extract(rar, { context, bytes, length in
                    guard let context, let bytes else { return 0 }
                    let sink = Unmanaged<Sink>.fromOpaque(context).takeUnretainedValue()
                    do {
                        try sink.handle.write(contentsOf: UnsafeBufferPointer(start: bytes, count: length))
                        return 1
                    } catch {
                        sink.failed = true
                        return 0
                    }
                }, context)

                if sink.failed { throw ExtractError.writeFailed(name) }
                guard result == TANKOBON_RAR_OK else { throw error(for: result, name: name) }
                writtenBytes += Double((try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }

            if totalBytes > 0 {
                progress(min(1, writtenBytes / totalBytes))
            }
        }
        progress(1)
    }

    private static func error(for code: Int32, name: String) -> ExtractError {
        switch code {
        case TANKOBON_RAR_BAD_ARCHIVE, TANKOBON_RAR_UNKNOWN_FORMAT, TANKOBON_RAR_EOPEN:
            .notARar(name)
        case TANKOBON_RAR_MISSING_PASSWORD, TANKOBON_RAR_BAD_PASSWORD:
            .encrypted(name)
        case TANKOBON_RAR_NEXT_VOLUME:
            .multipart(name)
        default:
            .damaged(name)
        }
    }
}
