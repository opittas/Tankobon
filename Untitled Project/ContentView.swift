import SwiftUI
import UIKit
import UniformTypeIdentifiers
import BookKit
import Observation

/// Tela principal: a biblioteca com os arquivos importados.
struct ContentView: View {
    @State private var library = LibraryModel()
    @State private var isImporting = false
    @State private var importMode = ImportMode.mangaArchives

    enum ImportMode {
        case mangaArchives
        case mangaFolder
        case files

        var contentTypes: [UTType] {
            switch self {
            case .mangaArchives: [UTType.zip, UTType(filenameExtension: "cbz")].compactMap { $0 }
            case .mangaFolder: [.folder]
            case .files: [.pdf, .epub]
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let conversion = library.conversion {
                    Section {
                        ConversionProgressView(conversion: conversion)
                    }
                }

                ForEach(library.items) { item in
                    NavigationLink(value: item) {
                        BookRow(item: item)
                    }
                }
                .onDelete(perform: library.delete)
            }
            .overlay {
                if library.items.isEmpty && library.conversion == nil {
                    ContentUnavailableView {
                        Label("Nenhum mangá ainda", systemImage: "books.vertical")
                    } description: {
                        Text("Escolha os ZIPs do mangá (um por volume) ou uma pasta. Cada volume vira um livro para o Apple Books.")
                    } actions: {
                        Button("Importar ZIP ou CBZ") { startImport(.mangaArchives) }
                            .buttonStyle(.borderedProminent)
                        Button("Importar pasta") { startImport(.mangaFolder) }
                    }
                }
            }
            .navigationTitle("Biblioteca")
            .navigationDestination(for: BookItem.self) { item in
                BookDetailView(item: item)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Mangá em ZIP ou CBZ", systemImage: "doc.zipper") { startImport(.mangaArchives) }
                        Button("Pasta de mangá", systemImage: "folder.badge.plus") { startImport(.mangaFolder) }
                        Divider()
                        Button("PDF ou EPUB", systemImage: "doc.badge.plus") { startImport(.files) }
                    } label: {
                        Label("Importar", systemImage: "plus")
                    }
                    .disabled(library.conversion != nil)
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: importMode.contentTypes,
                allowsMultipleSelection: importMode != .mangaFolder
            ) { result in
                switch result {
                case .success(let urls):
                    if importMode == .files {
                        library.importFiles(urls)
                    } else {
                        library.convertManga(urls)
                    }
                case .failure(let error):
                    library.errorMessage = error.localizedDescription
                }
            }
            .alert("Algo deu errado", isPresented: $library.showsError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(library.errorMessage ?? "")
            }
            .task {
                library.load()
            }
        }
    }

    private func startImport(_ mode: ImportMode) {
        importMode = mode
        isImporting = true
    }
}

/// Uma linha da lista: ícone, título, formato e tamanho.
struct BookRow: View {
    let item: BookItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.format.symbolName)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(item.format.displayName) · \(item.fileSize.formatted(.byteCount(style: .file)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Barra de progresso mostrada no topo da lista durante a conversão.
struct ConversionProgressView: View {
    let conversion: LibraryModel.Conversion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Convertendo “\(conversion.title)”", systemImage: "wand.and.stars")
                .font(.headline)
            if conversion.count > 1 {
                Text("Volume \(conversion.index) de \(conversion.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: conversion.progress)
            Text("\(Int(conversion.progress * 100))% · mantenha o app aberto até terminar")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Modelo da biblioteca

/// Liga a tela da biblioteca aos arquivos guardados pelo BookKit.
@Observable
final class LibraryModel {
    struct Conversion {
        var title: String
        var progress: Double
        var index = 1
        var count = 1
    }

    private(set) var items: [BookItem] = []
    private(set) var conversion: Conversion?
    var errorMessage: String?

    /// Controla o alerta de erro na tela.
    var showsError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    private let store = LibraryStore.standard

    /// Lê de novo a pasta da biblioteca.
    func load() {
        do {
            items = try store.items()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Converte o que foi escolhido (ZIPs, CBZs ou pastas) em um EPUB por volume, um de cada vez.
    func convertManga(_ selection: [URL]) {
        guard conversion == nil, !selection.isEmpty else { return }
        let store = store
        conversion = Conversion(title: "Preparando…", progress: 0)
        // Impede a tela de apagar sozinha no meio da conversão.
        UIApplication.shared.isIdleTimerDisabled = true
        // Arquivos de fora do app precisam desta permissão para serem lidos.
        let accessed = selection.filter { $0.startAccessingSecurityScopedResource() }

        Task {
            var failures: [String] = []
            do {
                let volumes = try await Self.findVolumes(in: selection)
                if volumes.isEmpty {
                    failures.append("Não encontrei imagens nem arquivos ZIP/CBZ no que você escolheu.")
                }
                for (offset, volume) in volumes.enumerated() {
                    let number = offset + 1
                    let title = MangaImport.title(of: volume)
                    conversion = Conversion(title: title, progress: 0, index: number, count: volumes.count)
                    do {
                        try await Self.convert(volume, store: store) { [weak self] value in
                            Task { @MainActor in
                                // Ignora atualizações atrasadas de um volume anterior.
                                if self?.conversion?.index == number {
                                    self?.conversion?.progress = value
                                }
                            }
                        }
                        // Cada volume aparece na lista assim que fica pronto.
                        load()
                    } catch {
                        failures.append("“\(title)”: \(error.localizedDescription)")
                    }
                }
            } catch {
                failures.append(error.localizedDescription)
            }

            for url in accessed {
                url.stopAccessingSecurityScopedResource()
            }
            UIApplication.shared.isIdleTimerDisabled = false
            conversion = nil
            load()
            if !failures.isEmpty {
                errorMessage = "Alguns volumes não foram convertidos:\n\n" + failures.joined(separator: "\n\n")
            }
        }
    }

    // O trabalho pesado roda fora da tela, para o app não travar.

    private nonisolated static func findVolumes(in selection: [URL]) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            try MangaImport.volumes(in: selection)
        }.value
    }

    private nonisolated static func convert(
        _ volume: URL,
        store: LibraryStore,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            _ = try MangaImport.convert(volume, into: store, progress: progress)
        }.value
    }

    /// Copia para a biblioteca os arquivos escolhidos no app Arquivos.
    func importFiles(_ urls: [URL]) {
        var failures: [String] = []
        for url in urls {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            do {
                try store.importFile(from: url)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            errorMessage = "Não foi possível importar:\n" + failures.joined(separator: "\n")
        }
        load()
    }

    /// Apaga os itens deslizados para a esquerda na lista.
    func delete(at offsets: IndexSet) {
        for index in offsets {
            do {
                try store.delete(items[index])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        load()
    }
}

// MARK: - Tela de detalhes

/// Detalhes de um arquivo e o botão para enviá-lo ao Apple Books.
struct BookDetailView: View {
    let item: BookItem

    var body: some View {
        Form {
            Section {
                LabeledContent("Formato", value: item.format.displayName)
                LabeledContent("Tamanho", value: item.fileSize.formatted(.byteCount(style: .file)))
                LabeledContent("Importado em", value: item.addedAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section {
                if item.format.opensInBooks {
                    ShareLink(item: item.url) {
                        Label("Abrir no Books", systemImage: "book")
                    }
                } else {
                    Label("Este formato precisa ser convertido antes de ir para o Books. A conversão chega nas próximas etapas.", systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if item.format.opensInBooks {
                    Text("Na janela que abrir, escolha o app Livros.")
                }
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Tipos de arquivo

extension BookFormat {
    /// Tipos de arquivo que aparecem no seletor do app Arquivos.
    static var supportedContentTypes: [UTType] {
        allCases.compactMap { UTType(filenameExtension: $0.rawValue) }
    }
}

#Preview {
    ContentView()
}
