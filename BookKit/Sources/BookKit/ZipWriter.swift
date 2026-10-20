import Foundation

/// Escreve um arquivo ZIP sem compressão (método "stored").
///
/// Um EPUB é um ZIP. As imagens de mangá (JPEG/PNG) já são comprimidas,
/// então guardá-las sem comprimir de novo não aumenta o tamanho
/// e mantém cada byte da imagem original intacto.
final class ZipWriter {
    enum ZipError: LocalizedError {
        case tooLarge

        var errorDescription: String? {
            "O livro passou de 4 GB, o limite do formato. Tente converter uma pasta menor (um volume por vez)."
        }
    }

    private struct Entry {
        let name: Data
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private let handle: FileHandle
    private var offset: UInt64 = 0
    private var entries: [Entry] = []

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    func add(path: String, text: String) throws {
        try add(path: path, data: Data(text.utf8))
    }

    func add(path: String, data: Data) throws {
        let name = Data(path.utf8)
        guard offset + UInt64(data.count) + 4096 < UInt64(UInt32.max),
              entries.count < Int(UInt16.max) - 1 else {
            throw ZipError.tooLarge
        }
        let crc = CRC32.checksum(data)
        entries.append(Entry(name: name, crc: crc, size: UInt32(data.count), offset: UInt32(offset)))

        var header = Data()
        header.appendUInt32(0x0403_4b50)   // assinatura do cabeçalho local
        header.appendUInt16(20)            // versão necessária
        header.appendUInt16(0)             // flags
        header.appendUInt16(0)             // método 0 = sem compressão
        header.appendUInt16(0)             // hora
        header.appendUInt16(0x21)          // data: 01/01/1980
        header.appendUInt32(crc)
        header.appendUInt32(UInt32(data.count))
        header.appendUInt32(UInt32(data.count))
        header.appendUInt16(UInt16(name.count))
        header.appendUInt16(0)             // sem campo extra
        header.append(name)

        try write(header)
        try write(data)
    }

    /// Grava o índice do ZIP e fecha o arquivo.
    func finish() throws {
        let directoryStart = offset
        var directory = Data()
        for entry in entries {
            directory.appendUInt32(0x0201_4b50) // assinatura do índice
            directory.appendUInt16(20)          // versão que criou
            directory.appendUInt16(20)          // versão necessária
            directory.appendUInt16(0)           // flags
            directory.appendUInt16(0)           // método
            directory.appendUInt16(0)           // hora
            directory.appendUInt16(0x21)        // data
            directory.appendUInt32(entry.crc)
            directory.appendUInt32(entry.size)
            directory.appendUInt32(entry.size)
            directory.appendUInt16(UInt16(entry.name.count))
            directory.appendUInt16(0)           // extra
            directory.appendUInt16(0)           // comentário
            directory.appendUInt16(0)           // disco
            directory.appendUInt16(0)           // atributos internos
            directory.appendUInt32(0)           // atributos externos
            directory.appendUInt32(entry.offset)
            directory.append(entry.name)
        }
        try write(directory)

        var end = Data()
        end.appendUInt32(0x0605_4b50)           // fim do índice
        end.appendUInt16(0)
        end.appendUInt16(0)
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt32(UInt32(directory.count))
        end.appendUInt32(UInt32(directoryStart))
        end.appendUInt16(0)
        try write(end)
        try handle.close()
    }

    /// Fecha o arquivo sem terminar (usado quando a conversão falha).
    func cancel() {
        try? handle.close()
    }

    private func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
        offset += UInt64(data.count)
    }
}

/// Soma de verificação que o formato ZIP exige para cada arquivo.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        table.withUnsafeBufferPointer { table in
            data.withUnsafeBytes { bytes in
                for byte in bytes {
                    crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
