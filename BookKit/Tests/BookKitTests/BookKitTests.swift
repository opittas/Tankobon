import Foundation
import Testing
@testable import BookKit

struct BookFormatTests {
    @Test func reconheceExtensoesSemDiferenciarMaiusculas() {
        #expect(BookFormat(url: URL(filePath: "/tmp/Livro.PDF")) == .pdf)
        #expect(BookFormat(url: URL(filePath: "/tmp/one-piece-01.cbz")) == .cbz)
        #expect(BookFormat(url: URL(filePath: "/tmp/livro.azw3")) == .azw3)
    }

    @Test func recusaExtensaoDesconhecida() {
        #expect(BookFormat(url: URL(filePath: "/tmp/foto.jpg")) == nil)
    }

    @Test func soPdfEEpubAbremDiretoNoBooks() {
        #expect(BookFormat.pdf.opensInBooks)
        #expect(BookFormat.epub.opensInBooks)
        #expect(!BookFormat.cbz.opensInBooks)
        #expect(!BookFormat.mobi.opensInBooks)
    }
}

struct LibraryStoreTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    private func makeFile(_ name: String) throws -> URL {
        let folder = root.appending(path: "origem")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data("teste".utf8).write(to: url)
        return url
    }

    @Test func importaECopiaOArquivo() throws {
        let store = LibraryStore(folder: root.appending(path: "Biblioteca"))
        let item = try store.importFile(from: makeFile("Livro.pdf"))

        #expect(item.format == .pdf)
        #expect(item.title == "Livro")
        #expect(item.fileSize == 5)
        #expect(try store.items().count == 1)
    }

    @Test func nomeRepetidoGanhaNumero() throws {
        let store = LibraryStore(folder: root.appending(path: "Biblioteca"))
        let source = try makeFile("Manga.cbz")
        try store.importFile(from: source)
        let second = try store.importFile(from: source)

        #expect(second.title == "Manga (2)")
        #expect(try store.items().count == 2)
    }

    @Test func recusaFormatoNaoSuportado() throws {
        let store = LibraryStore(folder: root.appending(path: "Biblioteca"))
        #expect(throws: LibraryError.unsupportedFormat("jpg")) {
            try store.importFile(from: makeFile("foto.jpg"))
        }
    }

    @Test func apagaArquivo() throws {
        let store = LibraryStore(folder: root.appending(path: "Biblioteca"))
        let item = try store.importFile(from: makeFile("Livro.epub"))
        try store.delete(item)

        #expect(try store.items().isEmpty)
    }
}
