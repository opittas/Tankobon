# Ícone do Tankobon

- **Claro** (modo claro do iOS): capa azul-marinho, kanji creme, fundo creme.
- **Escuro** (modo escuro do iOS): capa creme, kanji azul-marinho, fundo azul-noite.
- O formato e a posição de tudo são iguais nas duas; só mudam as cores.

## Camadas (para o Icon Composer)

Cada pasta (`claro/`, `escuro/`) tem uma camada por arquivo, de trás para a frente:

1. `1-fundo.svg` — cor de fundo
2. `2-fita.svg` — fita vermelha
3. `3-capa.svg` — capa do livro
4. `4-kanji.svg` — o kanji 本 (já convertido em contorno)

`Icone-claro.svg` / `Icone-escuro.svg` e os `.png` de 1024 px são o ícone pronto, com tudo junto.

## Cores

| Nome | Hex |
| --- | --- |
| Azul-marinho | `#22385E` |
| Creme | `#F2EBDD` |
| Vermelho (fita) | `#C8372D` |
| Azul-noite (fundo escuro) | `#1B2D4D` |

## Créditos

O kanji usa a fonte **Shippori Mincho B1 ExtraBold** (Fontdasu), licença SIL Open Font License 1.1, que permite usar em apps.
