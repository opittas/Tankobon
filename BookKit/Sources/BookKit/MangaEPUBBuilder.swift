import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Monta um EPUB de layout fixo a partir das imagens de um mangá.
///
/// - Cada imagem vira uma página com exatamente o tamanho dela: nada é cortado nem esticado.
/// - JPEG, PNG e GIF entram byte a byte, sem perder qualidade.
/// - Formatos que o Apple Books não abre (WebP, HEIC, AVIF...) viram JPEG de qualidade 95%.
/// - Com `rightToLeft`, o livro abre e avança da direita para a esquerda, como um mangá.
/// - Imagens mais largas que altas (páginas duplas) ficam centralizadas e inteiras.
public struct MangaEPUBBuilder: Sendable {
    public enum BuildError: LocalizedError {
        case noImages
        case unreadableImage(String)

        public var errorDescription: String? {
            switch self {
            case .noImages:
                "Não encontrei nenhuma imagem nessa pasta nem nas subpastas."
            case .unreadableImage(let name):
                "Não consegui ler a imagem \(name). Se a pasta estiver no iCloud, deixe-a baixada no aparelho e tente de novo."
            }
        }
    }

    public var rightToLeft: Bool

    public init(rightToLeft: Bool = true) {
        self.rightToLeft = rightToLeft
    }

    /// Cria o EPUB em `output` e devolve o número de páginas.
    /// `progress` recebe valores de 0 a 1 enquanto as páginas são processadas.
    @discardableResult
    public func build(
        chapters: [MangaChapter],
        title: String,
        to output: URL,
        progress: @Sendable (Double) -> Void = { _ in }
    ) throws -> Int {
        let total = chapters.reduce(0) { $0 + $1.pages.count }
        guard total > 0 else { throw BuildError.noImages }

        // O Apple Books usa o tamanho da primeira página como "moldura" de todas.
        // Por isso todas as páginas recebem a mesma moldura (o tamanho mais comum),
        // e cada imagem é encaixada inteira e centralizada dentro dela.
        let sizes = try chapters.flatMap(\.pages).map { url in
            try autoreleasepool { try PixelSize(imageAt: url) }
        }
        let canvas = PixelSize.canvas(for: sizes)

        let zip = try ZipWriter(url: output)
        do {
            // O "mimetype" precisa ser o primeiro arquivo e sem compressão.
            try zip.add(path: "mimetype", text: "application/epub+zip")
            try zip.add(path: "META-INF/container.xml", text: EPUBTemplates.container)
            try zip.add(path: "META-INF/com.apple.ibooks.display-options.xml", text: EPUBTemplates.appleDisplayOptions)

            var manifest = ""
            var spine = ""
            var tocLinks = ""
            var pageNumber = 0

            for chapter in chapters {
                for (indexInChapter, url) in chapter.pages.enumerated() {
                    pageNumber += 1
                    let id = String(pageNumber).leftPadded(to: 4)

                    // O autoreleasepool libera a memória de cada imagem antes da próxima.
                    let image = try autoreleasepool { try PreparedImage(url: url) }
                    let imageFile = "\(id).\(image.fileExtension)"

                    try zip.add(path: "OEBPS/images/\(imageFile)", data: image.data)
                    try zip.add(
                        path: "OEBPS/pages/p\(id).xhtml",
                        text: EPUBTemplates.page(
                            number: pageNumber,
                            imageFile: imageFile,
                            canvas: canvas,
                            frame: canvas.fitting(image.size)
                        )
                    )

                    let coverProperty = pageNumber == 1 ? #" properties="cover-image""# : ""
                    manifest += #"    <item id="img\#(id)" href="images/\#(imageFile)" media-type="\#(image.mediaType)"\#(coverProperty)/>"# + "\n"
                    manifest += #"    <item id="p\#(id)" href="pages/p\#(id).xhtml" media-type="application/xhtml+xml"/>"# + "\n"

                    let spreadProperty = image.size.width > image.size.height ? #" properties="rendition:page-spread-center""# : ""
                    spine += #"    <itemref idref="p\#(id)"\#(spreadProperty)/>"# + "\n"

                    if indexInChapter == 0 {
                        tocLinks += #"      <li><a href="pages/p\#(id).xhtml">\#(chapter.title.xmlEscaped)</a></li>"# + "\n"
                    }
                    progress(Double(pageNumber) / Double(total))
                }
            }

            try zip.add(path: "OEBPS/nav.xhtml", text: EPUBTemplates.nav(title: title, links: tocLinks))
            try zip.add(
                path: "OEBPS/content.opf",
                text: EPUBTemplates.packageDocument(title: title, manifest: manifest, spine: spine, rightToLeft: rightToLeft)
            )
            try zip.finish()
        } catch {
            zip.cancel()
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        return total
    }
}

// MARK: - Tamanho das páginas

/// Largura e altura de uma imagem, em pixels.
struct PixelSize: Hashable {
    var width: Int
    var height: Int

    /// Lê só o tamanho da imagem, sem carregá-la inteira na memória.
    init(imageAt url: URL) throws {
        let info = try ImageInfo(url: url)
        self = info.size
    }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Escolhe a moldura do livro: o tamanho de página em pé mais comum.
    /// Em caso de empate, fica o maior (para não reduzir as páginas à toa).
    static func canvas(for sizes: [PixelSize]) -> PixelSize {
        let portrait = sizes.filter { $0.width <= $0.height }
        let candidates = portrait.isEmpty ? sizes : portrait
        var counts: [PixelSize: Int] = [:]
        for size in candidates {
            counts[size, default: 0] += 1
        }
        return counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key.width * lhs.key.height < rhs.key.width * rhs.key.height
        }?.key ?? PixelSize(width: 1200, height: 1800)
    }

    /// Posição e tamanho para encaixar uma imagem inteira, centralizada, dentro desta moldura.
    func fitting(_ image: PixelSize) -> PageFrame {
        let scale = min(Double(width) / Double(image.width), Double(height) / Double(image.height))
        let fittedWidth = min(width, Int((Double(image.width) * scale).rounded()))
        let fittedHeight = min(height, Int((Double(image.height) * scale).rounded()))
        return PageFrame(
            x: (width - fittedWidth) / 2,
            y: (height - fittedHeight) / 2,
            width: fittedWidth,
            height: fittedHeight
        )
    }
}

/// Onde a imagem fica dentro da página.
struct PageFrame: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}

/// Informações lidas do cabeçalho da imagem.
struct ImageInfo {
    let source: CGImageSource
    let size: PixelSize
    let orientation: Int

    init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else {
            throw MangaEPUBBuilder.BuildError.unreadableImage(url.lastPathComponent)
        }
        self.source = source
        // Imagens giradas pela câmera (orientação 5 a 8) trocam largura e altura.
        orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        size = orientation >= 5 ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
    }
}

// MARK: - Imagem pronta para o EPUB

struct PreparedImage {
    let data: Data
    let size: PixelSize
    let fileExtension: String
    let mediaType: String

    init(url: URL) throws {
        let info = try ImageInfo(url: url)
        let source = info.source
        let orientation = info.orientation
        size = info.size

        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            data = try Data(contentsOf: url)
            fileExtension = "jpg"
            mediaType = "image/jpeg"
        case "png":
            data = try Data(contentsOf: url)
            fileExtension = "png"
            mediaType = "image/png"
        case "gif":
            data = try Data(contentsOf: url)
            fileExtension = "gif"
            mediaType = "image/gif"
        default:
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw MangaEPUBBuilder.BuildError.unreadableImage(url.lastPathComponent)
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw MangaEPUBBuilder.BuildError.unreadableImage(url.lastPathComponent)
            }
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: 0.95,
                kCGImagePropertyOrientation: orientation,
            ]
            CGImageDestinationAddImage(destination, image, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw MangaEPUBBuilder.BuildError.unreadableImage(url.lastPathComponent)
            }
            data = output as Data
            fileExtension = "jpg"
            mediaType = "image/jpeg"
        }
    }
}

// MARK: - Textos fixos do EPUB

enum EPUBTemplates {
    static let container = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    /// Arquivo que o Apple Books lê para tratar o livro como layout fixo.
    static let appleDisplayOptions = """
    <?xml version="1.0" encoding="UTF-8"?>
    <display_options>
      <platform name="*">
        <option name="fixed-layout">true</option>
        <option name="open-to-spread">false</option>
      </platform>
    </display_options>
    """

    static func page(number: Int, imageFile: String, canvas: PixelSize, frame: PageFrame) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head>
          <meta charset="UTF-8"/>
          <title>Página \(number)</title>
          <meta name="viewport" content="width=\(canvas.width), height=\(canvas.height)"/>
          <style>
            html, body { margin: 0; padding: 0; width: \(canvas.width)px; height: \(canvas.height)px; overflow: hidden; background: #fff; }
            img { position: absolute; left: \(frame.x)px; top: \(frame.y)px; width: \(frame.width)px; height: \(frame.height)px; }
          </style>
        </head>
        <body>
          <img src="../images/\(imageFile)" alt="Página \(number)"/>
        </body>
        </html>
        """
    }

    static func nav(title: String, links: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head>
          <meta charset="UTF-8"/>
          <title>\(title.xmlEscaped)</title>
        </head>
        <body>
          <nav epub:type="toc" id="toc">
            <h1>Sumário</h1>
            <ol>
        \(links)    </ol>
          </nav>
        </body>
        </html>
        """
    }

    static func packageDocument(title: String, manifest: String, spine: String, rightToLeft: Bool) -> String {
        let modified = ISO8601DateFormatter().string(from: Date())
        let direction = rightToLeft ? "rtl" : "ltr"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">urn:uuid:\(UUID().uuidString.lowercased())</dc:identifier>
            <dc:title>\(title.xmlEscaped)</dc:title>
            <dc:language>\(rightToLeft ? "ja" : "pt-BR")</dc:language>
            <meta property="dcterms:modified">\(modified)</meta>
            <meta property="rendition:layout">pre-paginated</meta>
            <meta property="rendition:orientation">auto</meta>
            <meta property="rendition:spread">landscape</meta>
            <meta name="cover" content="img0001"/>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        \(manifest)  </manifest>
          <spine page-progression-direction="\(direction)">
        \(spine)  </spine>
        </package>
        """
    }
}

extension String {
    /// Completa com zeros à esquerda: "7" vira "0007".
    func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }

    /// Troca caracteres especiais para não quebrar o XML (ex.: "&" em títulos).
    var xmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
