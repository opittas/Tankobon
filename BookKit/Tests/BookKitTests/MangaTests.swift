import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BookKit

struct MangaTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    /// Cria uma imagem PNG simples para os testes.
    private func makeImage(_ relativePath: String, width: Int = 60, height: Int = 90) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test func ordemNaturalComoNoFinder() throws {
        try makeImage("Manga/10.png")
        try makeImage("Manga/2.png")
        try makeImage("Manga/1.png")

        let chapters = try MangaFolderScanner.scan(root.appending(path: "Manga"))

        #expect(chapters.count == 1)
        #expect(chapters[0].pages.map(\.lastPathComponent) == ["1.png", "2.png", "10.png"])
    }

    @Test func leSubpastasComoCapitulos() throws {
        try makeImage("Manga/capa.png")
        try makeImage("Manga/Vol 1/Cap 2/01.png")
        try makeImage("Manga/Vol 1/Cap 10/01.png")
        try makeImage("Manga/Vol 1/Cap 1/01.png")
        try makeImage("Manga/Vol 1/Cap 1/02.png")
        try Data("x".utf8).write(to: root.appending(path: "Manga/Vol 1/Cap 1/leia-me.txt"))

        let chapters = try MangaFolderScanner.scan(root.appending(path: "Manga"))

        #expect(chapters.map(\.title) == ["Manga", "Vol 1 › Cap 1", "Vol 1 › Cap 2", "Vol 1 › Cap 10"])
        #expect(chapters.map(\.pages.count) == [1, 2, 1, 1])
    }

    @Test func geraEpubDeMangaValido() throws {
        try makeImage("Manga/Cap 1/01.png")
        try makeImage("Manga/Cap 1/02.png", width: 120, height: 90) // página dupla
        let chapters = try MangaFolderScanner.scan(root.appending(path: "Manga"))
        let output = root.appending(path: "Manga.epub")

        let pages = try MangaEPUBBuilder().build(chapters: chapters, title: "Manga", to: output)
        let data = try Data(contentsOf: output)

        #expect(pages == 2)
        // O "mimetype" é o primeiro arquivo do ZIP, sem compressão.
        #expect(data[0..<4] == Data([0x50, 0x4B, 0x03, 0x04]))
        #expect(String(decoding: data[30..<38], as: UTF8.self) == "mimetype")
        #expect(String(decoding: data[38..<58], as: UTF8.self) == "application/epub+zip")
        // Leitura da direita para a esquerda, layout fixo e página dupla centralizada.
        #expect(data.range(of: Data(#"page-progression-direction="rtl""#.utf8)) != nil)
        #expect(data.range(of: Data("pre-paginated".utf8)) != nil)
        #expect(data.range(of: Data("rendition:page-spread-center".utf8)) != nil)
        #expect(data.range(of: Data("width=60, height=90".utf8)) != nil)
    }

    @Test func todasAsPaginasUsamAMesmaMolduraSemCortar() throws {
        try makeImage("Manga/00-capa.png", width: 100, height: 140) // capa de tamanho diferente
        try makeImage("Manga/01.png")
        try makeImage("Manga/02.png")
        try makeImage("Manga/03.png", width: 80, height: 100)
        let chapters = try MangaFolderScanner.scan(root.appending(path: "Manga"))
        let output = root.appending(path: "Manga.epub")

        try MangaEPUBBuilder().build(chapters: chapters, title: "Manga", to: output)
        let text = String(decoding: try Data(contentsOf: output), as: UTF8.self)

        // A moldura é o tamanho mais comum (60x90) em TODAS as 4 páginas, inclusive na capa.
        #expect(text.components(separatedBy: "width=60, height=90").count - 1 == 4)
        // A capa (100x140) é reduzida para caber inteira: 60/100 = 0,6 → 60x84, centralizada.
        #expect(text.contains("left: 0px; top: 3px; width: 60px; height: 84px;"))
        // A página 80x100 também cabe inteira: 60/80 = 0,75 → 60x75.
        #expect(text.contains("left: 0px; top: 7px; width: 60px; height: 75px;"))
    }

    @Test func encaixeNuncaPassaDaMoldura() {
        let canvas = PixelSize(width: 1200, height: 1800)
        let wide = canvas.fitting(PixelSize(width: 2400, height: 1800)) // página dupla
        #expect(wide == PageFrame(x: 0, y: 450, width: 1200, height: 900))
        let small = canvas.fitting(PixelSize(width: 600, height: 900))
        #expect(small == PageFrame(x: 0, y: 0, width: 1200, height: 1800))
    }

    @Test func pastaSemImagensDaErro() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "Vazia"), withIntermediateDirectories: true)
        let chapters = try MangaFolderScanner.scan(root.appending(path: "Vazia"))

        #expect(throws: MangaEPUBBuilder.BuildError.self) {
            try MangaEPUBBuilder().build(chapters: chapters, title: "Vazia", to: root.appending(path: "Vazia.epub"))
        }
    }

    @Test func crcConfereComValorConhecido() {
        // CRC32 de "123456789" é 0xCBF43926 (valor padrão de referência).
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }
}
