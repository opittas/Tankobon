# Tankobon

App para iPhone e iPad que converte livros e mangás para formatos que o **Apple Books** consegue abrir. Mangás são detectados e configurados para leitura da **direita para a esquerda**.

Feito em SwiftUI, com toda a conversão no próprio aparelho: nenhum arquivo é enviado para a internet.

## Formatos

| Entrada | Saída |
| --- | --- |
| CBZ, CBR | EPUB de layout fixo (mangá em RTL) |
| PDF escaneado | EPUB de layout fixo |
| PDF de texto | PDF com título, autor e capa ajustados |
| EPUB | EPUB (sentido de leitura e metadados ajustados) |
| MOBI, AZW3 | EPUB ajustável |

> Arquivos com DRM não são convertidos.

## Estrutura

- `Tankobon/` — o app (telas em SwiftUI)
- `BookKit/` — pacote Swift com toda a lógica de conversão, sem telas

## Roteiro

- [x] 0. Projeto, pacote BookKit e repositório no GitHub
- [ ] 1. Importar arquivo e enviar ao Books
- [ ] 2. CBZ → EPUB de mangá (RTL)
- [ ] 3. Detecção de mangá
- [ ] 4. PDF escaneado → EPUB
- [ ] 5. EPUB de entrada
- [ ] 6. CBR
- [ ] 7. MOBI
- [ ] 8. AZW3 (KF8)
- [ ] 9. Acabamento

## Requisitos

- Xcode recente
- iOS 18 ou superior
