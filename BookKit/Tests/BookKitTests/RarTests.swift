import CUnrar
import Foundation
import Testing
@testable import BookKit

/// Testes do leitor de RAR (UnRAR oficial) com arquivos RAR reais.
struct RarTests {
    private func fixture(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "rar", subdirectory: "Fixtures"))
    }

    /// Lê todos os arquivos de um RAR pela ponte em C e devolve nome → tamanho.
    private func readAll(_ url: URL) throws -> [String: Int] {
        var result: Int32 = 0
        let rar = try #require(url.withUnsafeFileSystemRepresentation { tankobon_rar_open($0, &result) })
        defer { tankobon_rar_close(rar) }

        final class Counter { var bytes = 0 }
        var files: [String: Int] = [:]
        var name = [CChar](repeating: 0, count: 4096)
        var isDirectory: Int32 = 0
        var isEncrypted: Int32 = 0
        while tankobon_rar_next(rar, &name, 4096, &isDirectory, &isEncrypted) == TANKOBON_RAR_OK {
            let counter = Counter()
            let code = tankobon_rar_extract(rar, { context, _, length in
                Unmanaged<Counter>.fromOpaque(context!).takeUnretainedValue().bytes += length
                return 1
            }, Unmanaged.passUnretained(counter).toOpaque())
            #expect(code == TANKOBON_RAR_OK)
            files[String(cString: name)] = counter.bytes
        }
        return files
    }

    @Test func abreRar4Solido() throws {
        // O modo "sólido" do RAR antigo era o que a libarchive não abria.
        let files = try readAll(fixture("rar3-solid"))
        #expect(files == ["stest1.txt": 2048, "stest2.txt": 2048])
    }

    @Test func abreRar5Solido() throws {
        let files = try readAll(fixture("rar5-solid"))
        #expect(files == ["stest1.txt": 2048, "stest2.txt": 2048])
    }

    @Test func pulaArquivosEmRarSolido() throws {
        var result: Int32 = 0
        let rar = try #require(try fixture("rar3-solid").withUnsafeFileSystemRepresentation { tankobon_rar_open($0, &result) })
        defer { tankobon_rar_close(rar) }
        var name = [CChar](repeating: 0, count: 4096)
        var isDirectory: Int32 = 0
        var isEncrypted: Int32 = 0

        #expect(tankobon_rar_next(rar, &name, 4096, &isDirectory, &isEncrypted) == TANKOBON_RAR_OK)
        #expect(tankobon_rar_skip(rar) == TANKOBON_RAR_OK)
        #expect(tankobon_rar_next(rar, &name, 4096, &isDirectory, &isEncrypted) == TANKOBON_RAR_OK)
        #expect(String(cString: name) == "stest2.txt")
    }

    @Test func rarComSenhaDaErroClaro() throws {
        let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        // Ponte em C: avisa que precisa de senha.
        var result: Int32 = 0
        let rar = try #require(try fixture("rar5-psw").withUnsafeFileSystemRepresentation { tankobon_rar_open($0, &result) })
        var name = [CChar](repeating: 0, count: 4096)
        var isDirectory: Int32 = 0
        var isEncrypted: Int32 = 0
        #expect(tankobon_rar_next(rar, &name, 4096, &isDirectory, &isEncrypted) == TANKOBON_RAR_OK)
        #expect(isEncrypted != 0)
        #expect(tankobon_rar_extract(rar, { _, _, _ in 1 }, nil) == TANKOBON_RAR_MISSING_PASSWORD)
        tankobon_rar_close(rar)
        // O extrator só procura imagens; esse RAR só tem .txt, então não extrai nada e não quebra.
        try RarExtractor.extract(try fixture("rar5-psw"), to: destination)
    }

    @Test func reconheceOTipoPeloConteudo() throws {
        #expect(MangaImport.ArchiveKind(of: try fixture("rar5-solid")) == .rar)
        // Um RAR com nome de ".cbz" continua sendo reconhecido como RAR.
        let renamed = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).cbz")
        try FileManager.default.copyItem(at: try fixture("rar3-solid"), to: renamed)
        #expect(MangaImport.ArchiveKind(of: renamed) == .rar)
    }
}
