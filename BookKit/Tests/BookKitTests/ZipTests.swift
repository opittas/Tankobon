import Compression
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BookKit

struct ZipTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    private func pngData(width: Int = 60, height: Int = 90) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// Monta um ZIP "como o do site": pasta embrulho, capítulos, lixo do Mac e um caminho malicioso.
    private func makeVolumeZip(named name: String, includeMaliciousPath: Bool = true) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: name)
        let zip = try ZipWriter(url: url)
        let png = try pngData()
        try zip.add(path: "Tokyo Ghoul v01/", data: Data())
        try zip.add(path: "Tokyo Ghoul v01/Cap 2/01.png", data: png)
        try zip.add(path: "Tokyo Ghoul v01/Cap 1/02.png", data: png)
        try zip.add(path: "Tokyo Ghoul v01/Cap 1/01.png", data: png)
        try zip.add(path: "Tokyo Ghoul v01/Cap 1/leia-me.txt", text: "não é imagem")
        try zip.add(path: "__MACOSX/Tokyo Ghoul v01/Cap 1/._01.png", data: Data([0, 1, 2]))
        if includeMaliciousPath {
            try zip.add(path: "../fora-da-pasta.png", data: png)
        }
        try zip.finish()
        return url
    }

    @Test func extraiSoAsImagensComSeguranca() throws {
        let archive = try makeVolumeZip(named: "Vol 1.zip")
        let destination = root.appending(path: "extraido")

        try ZipExtractor.extract(archive, to: destination)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: destination.appending(path: "Tokyo Ghoul v01/Cap 1/01.png").path(percentEncoded: false)))
        #expect(!fm.fileExists(atPath: destination.appending(path: "Tokyo Ghoul v01/Cap 1/leia-me.txt").path(percentEncoded: false)))
        #expect(!fm.fileExists(atPath: destination.appending(path: "__MACOSX").path(percentEncoded: false)))
        // "../" é ignorado: o arquivo fica dentro da pasta de destino, nunca fora dela.
        #expect(!fm.fileExists(atPath: root.appending(path: "fora-da-pasta.png").path(percentEncoded: false)))
    }

    @Test func zipViraEpubComCapitulosEmOrdem() throws {
        let archive = try makeVolumeZip(named: "Tokyo Ghoul Vol 1.cbz", includeMaliciousPath: false)
        let store = LibraryStore(folder: root.appending(path: "Biblioteca"))

        let epub = try MangaImport.convert(archive, into: store)
        let text = String(decoding: try Data(contentsOf: epub), as: UTF8.self)

        #expect(epub.lastPathComponent == "Tokyo Ghoul Vol 1.epub")
        // 3 páginas: a pasta embrulho "Tokyo Ghoul v01" é atravessada e o .txt é ignorado.
        #expect(text.contains("<title>Página 3</title>"))
        #expect(!text.contains("<title>Página 4</title>"))
        #expect(text.contains(">Cap 1</a>"))
        #expect(text.contains(">Cap 2</a>"))
    }

    @Test func pastaComZipsViraUmVolumePorArquivo() throws {
        let series = root.appending(path: "Série")
        try FileManager.default.createDirectory(at: series, withIntermediateDirectories: true)
        for name in ["Vol 10.zip", "Vol 2.cbz", "Vol 1.zip", "capa.txt"] {
            try Data().write(to: series.appending(path: name))
        }

        let volumes = try MangaImport.volumes(in: [series])

        #expect(volumes.map(\.lastPathComponent) == ["Vol 1.zip", "Vol 2.cbz", "Vol 10.zip"])
    }

    @Test func descompactaDeflate() throws {
        // Monta à mão um ZIP com um arquivo comprimido em "deflate", o tipo mais comum.
        let original = Data(String(repeating: "Tankobon mangá ", count: 500).utf8)
        var compressed = Data(count: original.count + 512)
        let compressedSize = compressed.withUnsafeMutableBytes { destination in
            original.withUnsafeBytes { source in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, destination.count,
                    source.bindMemory(to: UInt8.self).baseAddress!, original.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        compressed = compressed.prefix(compressedSize)
        let name = Data("pagina.png".utf8)
        let crc = CRC32.checksum(original)

        var zip = Data()
        zip.appendUInt32(0x0403_4b50); zip.appendUInt16(20); zip.appendUInt16(0); zip.appendUInt16(8)
        zip.appendUInt16(0); zip.appendUInt16(0x21); zip.appendUInt32(crc)
        zip.appendUInt32(UInt32(compressed.count)); zip.appendUInt32(UInt32(original.count))
        zip.appendUInt16(UInt16(name.count)); zip.appendUInt16(0); zip.append(name); zip.append(compressed)
        let directoryOffset = zip.count
        var directory = Data()
        directory.appendUInt32(0x0201_4b50); directory.appendUInt16(20); directory.appendUInt16(20)
        directory.appendUInt16(0); directory.appendUInt16(8); directory.appendUInt16(0); directory.appendUInt16(0x21)
        directory.appendUInt32(crc); directory.appendUInt32(UInt32(compressed.count)); directory.appendUInt32(UInt32(original.count))
        directory.appendUInt16(UInt16(name.count)); directory.appendUInt16(0); directory.appendUInt16(0)
        directory.appendUInt16(0); directory.appendUInt16(0); directory.appendUInt32(0); directory.appendUInt32(0)
        directory.append(name)
        zip.append(directory)
        zip.appendUInt32(0x0605_4b50); zip.appendUInt16(0); zip.appendUInt16(0); zip.appendUInt16(1); zip.appendUInt16(1)
        zip.appendUInt32(UInt32(directory.count)); zip.appendUInt32(UInt32(directoryOffset)); zip.appendUInt16(0)

        let entries = try ZipExtractor.centralDirectory(of: zip, name: "teste.zip")
        #expect(entries.count == 1)
        let contents = try ZipExtractor.contents(of: entries[0], in: zip, name: "teste.zip")
        #expect(contents == original)
    }

    @Test func arquivoQueNaoEZipDaErroClaro() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fake = root.appending(path: "falso.zip")
        try Data("isto não é um zip".utf8).write(to: fake)

        #expect(throws: ZipExtractor.ExtractError.self) {
            try ZipExtractor.extract(fake, to: root.appending(path: "saida"))
        }
    }
}
