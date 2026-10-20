import Compression
import Foundation

/// Extrai as imagens de um arquivo ZIP ou CBZ.
///
/// Usa o framework Compression da Apple para descompactar (método "deflate"),
/// sem bibliotecas de fora. Só as imagens são extraídas, para economizar espaço.
enum ZipExtractor {
    enum ExtractError: LocalizedError {
        case notAZip(String)
        case damaged(String)
        case encrypted(String)
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .notAZip(let name):
                "“\(name)” não é um arquivo ZIP válido."
            case .damaged(let name):
                "O arquivo “\(name)” parece estar corrompido ou incompleto. Tente baixá-lo de novo."
            case .encrypted(let name):
                "O arquivo “\(name)” está protegido por senha."
            case .unsupported(let name):
                "O arquivo “\(name)” usa um tipo de compressão que o app ainda não abre."
            }
        }
    }

    struct Entry {
        let name: String
        let flags: UInt16
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// Extrai as imagens de `archive` para dentro de `destination`, mantendo as pastas.
    static func extract(_ archive: URL, to destination: URL, progress: (Double) -> Void = { _ in }) throws {
        let name = archive.lastPathComponent
        // "mappedIfSafe" lê o arquivo aos poucos, sem carregar tudo na memória.
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let entries = try centralDirectory(of: data, name: name)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        for (index, entry) in entries.enumerated() {
            try autoreleasepool {
                guard let relativePath = safeImagePath(entry.name) else { return }
                let target = destination.appending(path: relativePath)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try contents(of: entry, in: data, name: name).write(to: target)
            }
            progress(Double(index + 1) / Double(entries.count))
        }
    }

    /// Lê o índice do ZIP (a lista de arquivos que fica no final dele).
    static func centralDirectory(of data: Data, name: String) throws -> [Entry] {
        guard data.count >= 22 else { throw ExtractError.notAZip(name) }

        // O fim do índice fica nos últimos 22 bytes (ou um pouco antes, se houver comentário).
        var endRecord: Int?
        var position = data.count - 22
        let lowestPosition = max(0, data.count - 65_557)
        while position >= lowestPosition {
            if data.uint32(at: position) == 0x0605_4b50 {
                endRecord = position
                break
            }
            position -= 1
        }
        guard let end = endRecord else { throw ExtractError.notAZip(name) }

        var count = Int(data.uint16(at: end + 10))
        var directoryOffset = Int(data.uint32(at: end + 16))

        // ZIP64: usado por arquivos com mais de 4 GB ou muitos arquivos.
        if count == 0xFFFF || directoryOffset == 0xFFFF_FFFF,
           end >= 20, data.uint32(at: end - 20) == 0x0706_4b50 {
            let zip64End = Int(data.uint64(at: end - 20 + 8))
            guard zip64End + 56 <= data.count, data.uint32(at: zip64End) == 0x0606_4b50 else {
                throw ExtractError.damaged(name)
            }
            count = Int(data.uint64(at: zip64End + 32))
            directoryOffset = Int(data.uint64(at: zip64End + 48))
        }

        var entries: [Entry] = []
        var cursor = directoryOffset
        for _ in 0..<count {
            guard cursor + 46 <= data.count, data.uint32(at: cursor) == 0x0201_4b50 else {
                throw ExtractError.damaged(name)
            }
            let flags = data.uint16(at: cursor + 8)
            let method = data.uint16(at: cursor + 10)
            var compressedSize = UInt64(data.uint32(at: cursor + 20))
            var uncompressedSize = UInt64(data.uint32(at: cursor + 24))
            let nameLength = Int(data.uint16(at: cursor + 28))
            let extraLength = Int(data.uint16(at: cursor + 30))
            let commentLength = Int(data.uint16(at: cursor + 32))
            var offset = UInt64(data.uint32(at: cursor + 42))
            guard cursor + 46 + nameLength + extraLength <= data.count else {
                throw ExtractError.damaged(name)
            }

            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            let entryName = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? ""

            // Campo extra do ZIP64 com os tamanhos e a posição reais.
            var extra = cursor + 46 + nameLength
            let extraEnd = extra + extraLength
            while extra + 4 <= extraEnd {
                let id = data.uint16(at: extra)
                let size = Int(data.uint16(at: extra + 2))
                if id == 0x0001 {
                    var field = extra + 4
                    let fieldEnd = min(extra + 4 + size, extraEnd)
                    if uncompressedSize == 0xFFFF_FFFF, field + 8 <= fieldEnd {
                        uncompressedSize = data.uint64(at: field)
                        field += 8
                    }
                    if compressedSize == 0xFFFF_FFFF, field + 8 <= fieldEnd {
                        compressedSize = data.uint64(at: field)
                        field += 8
                    }
                    if offset == 0xFFFF_FFFF, field + 8 <= fieldEnd {
                        offset = data.uint64(at: field)
                    }
                }
                extra += 4 + size
            }

            if !entryName.hasSuffix("/") {
                entries.append(Entry(
                    name: entryName,
                    flags: flags,
                    method: method,
                    compressedSize: Int(compressedSize),
                    uncompressedSize: Int(uncompressedSize),
                    localHeaderOffset: Int(offset)
                ))
            }
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// Lê e descompacta um arquivo de dentro do ZIP.
    static func contents(of entry: Entry, in data: Data, name: String) throws -> Data {
        guard entry.flags & 1 == 0 else { throw ExtractError.encrypted(name) }

        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, data.uint32(at: header) == 0x0403_4b50 else {
            throw ExtractError.damaged(name)
        }
        let start = header + 30 + Int(data.uint16(at: header + 26)) + Int(data.uint16(at: header + 28))
        let end = start + entry.compressedSize
        guard end <= data.count else { throw ExtractError.damaged(name) }

        switch entry.method {
        case 0: // guardado sem compressão
            return data.subdata(in: start..<end)
        case 8: // deflate, o mais comum
            let size = entry.uncompressedSize
            guard size > 0 else { return Data() }
            var output = Data(count: size)
            let written = output.withUnsafeMutableBytes { destination in
                data.withUnsafeBytes { source in
                    compression_decode_buffer(
                        destination.bindMemory(to: UInt8.self).baseAddress!, size,
                        source.bindMemory(to: UInt8.self).baseAddress! + start, end - start,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            guard written == size else { throw ExtractError.damaged(name) }
            return output
        default:
            throw ExtractError.unsupported(name)
        }
    }

    /// Caminho seguro dentro da pasta de destino, só para imagens.
    /// Ignora "../" (que poderia escrever fora da pasta), `__MACOSX` e arquivos ocultos.
    static func safeImagePath(_ name: String) -> String? {
        let parts = name
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        guard let fileName = parts.last,
              !parts.contains(where: { $0.lowercased() == "__macosx" || $0.hasPrefix(".") }),
              MangaFolderScanner.imageExtensions.contains((fileName as NSString).pathExtension.lowercased())
        else { return nil }
        return parts.joined(separator: "/")
    }
}

extension Data {
    func uint16(at offset: Int) -> UInt16 {
        withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) }
    }

    func uint32(at offset: Int) -> UInt32 {
        withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }

    func uint64(at offset: Int) -> UInt64 {
        withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) }
    }
}
