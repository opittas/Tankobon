import Foundation

/// Formatos de arquivo que o Tankobon reconhece.
public enum BookFormat: String, CaseIterable, Sendable {
    case pdf, epub, mobi, azw3, cbz, cbr

    /// Descobre o formato pela extensão do arquivo (ex.: "Livro.PDF" vira `.pdf`).
    /// Retorna `nil` quando a extensão não é suportada.
    public init?(url: URL) {
        self.init(rawValue: url.pathExtension.lowercased())
    }

    /// Nome para mostrar na tela.
    public var displayName: String {
        rawValue.uppercased()
    }

    /// Ícone do SF Symbols usado na lista.
    public var symbolName: String {
        switch self {
        case .pdf: "doc.richtext"
        case .epub: "book.closed"
        case .mobi, .azw3: "book"
        case .cbz, .cbr: "photo.on.rectangle"
        }
    }

    /// `true` quando o Apple Books já abre o arquivo sem conversão.
    public var opensInBooks: Bool {
        self == .pdf || self == .epub
    }
}
