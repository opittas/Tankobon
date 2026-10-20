import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BookKit

/// Testes do leitor de RAR/7z (libarchive do sistema).
/// Não existe como criar RAR aqui (o formato é fechado), então os testes usam
/// ZIPs: a libarchive lê ZIP pelo mesmo caminho de código que usa para RAR.
struct ArchiveTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    private func pngData() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 60, height: 90, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 90))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func makeArchive(named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: name)
        let zip = try ZipWriter(url: url)
        let png = try pngData()
        try zip.add(path: "Volume 1/Cap 1/01.png", data: png)
        try zip.add(path: "Volume 1/Cap 1/02.png", data: png)
        try zip.add(path: "Volume 1/Cap 2/01.png", data: png)
        try zip.add(path: "Volume 1/creditos.txt", text: "não é imagem")
        try zip.add(path: "__MACOSX/Volume 1/._01.png", data: Data([0]))
        try zip.finish()
        return url
    }

    @Test func libarchiveExtraiSoAsImagens() throws {
        let archive = try makeArchive(named: "teste.zip")
        let destination = root.appending(path: "saida")

        try ArchiveExtractor.extract(archive, to: destination)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: destination.appending(path: "Volume 1/Cap 1/02.png").path(percentEncoded: false)))
        #expect(fm.fileExists(atPath: destination.appending(path: "Volume 1/Cap 2/01.png").path(percentEncoded: false)))
        #expect(!fm.fileExists(atPath: destination.appending(path: "Volume 1/creditos.txt").path(percentEncoded: false)))
        #expect(!fm.fileExists(atPath: destination.appending(path: "__MACOSX").path(percentEncoded: false)))
        let original = try pngData()
        #expect(try Data(contentsOf: destination.appending(path: "Volume 1/Cap 1/01.png")) == original)
    }

    @Test func extensaoTrocadaAindaFunciona() throws {
        // Muitos sites mandam ".cbr" que na verdade é ZIP (e vice-versa).
        let archive = try makeArchive(named: "Tokyo Ghoul Vol 1.cbr")
        let store = LibraryStore(folder: root.appending(path: "Biblioteca"))

        let epub = try MangaImport.convert(archive, into: store)
        let text = String(decoding: try Data(contentsOf: epub), as: UTF8.self)

        #expect(epub.lastPathComponent == "Tokyo Ghoul Vol 1.epub")
        #expect(text.contains("<title>Página 3</title>"))
        #expect(!text.contains("<title>Página 4</title>"))
    }

    @Test func rarEReconhecidoComoVolume() {
        #expect(MangaImport.isArchive(URL(filePath: "/tmp/Vol 1.rar")))
        #expect(MangaImport.isArchive(URL(filePath: "/tmp/Vol 1.CBR")))
        #expect(MangaImport.isArchive(URL(filePath: "/tmp/Vol 1.7z")))
        #expect(MangaImport.title(of: URL(filePath: "/tmp/One Piece v01.cbr")) == "One Piece v01")
    }

    @Test func arquivoInvalidoDaErroClaro() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fake = root.appending(path: "falso.rar")
        try Data("isto não é um rar".utf8).write(to: fake)

        #expect(throws: ArchiveExtractor.ExtractError.self) {
            try ArchiveExtractor.extract(fake, to: root.appending(path: "saida"))
        }
    }
}
