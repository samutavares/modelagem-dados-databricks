# Dados do projeto

Os arquivos que a Escala Viagens Corporativas recebe todo mês: os voos da ANAC e os cadastros que descrevem
empresas aéreas e aeroportos. Recorte do curso: voos de julho a outubro de 2026.

| Pasta | O que tem | Quando entra no curso |
|---|---|---|
| `vra/` | os voos de cada mês (Voo Regular Ativo, VRA, da ANAC), um arquivo por mês | aula 1 (outubro, na aula 3) |
| `vra_republicado/` | agosto republicado pela ANAC, com os voos que faltavam na primeira entrega | aula 4 |
| `cadastros/aerodromos/` | a lista de aeródromos públicos da ANAC em duas datas: abril de 2025 e novembro de 2026 | aulas 2 e 3 |
| `cadastros/aeroportos_exterior/` | os aeroportos do exterior que aparecem nos voos | aula 2 |
| `cadastros/empresas/` | as empresas aéreas brasileiras e estrangeiras autorizadas pela ANAC | aula 2 |
| `cadastros/concessoes/` | os contratos de concessão de aeroportos da ANAC | aula 3 |
| `cadastros/administradores/` | quem administra cada aeroporto e desde quando, em duas entregas: 30/09 e 31/10/2026 | aula 3 |

## `vra/`: os voos

Um arquivo por mês, `VRA_AAAAM.csv` (`VRA_20268.csv` é agosto de 2026). Cada linha é uma etapa de voo: uma
decolagem de um aeroporto com pouso em outro.

O arquivo não começa no cabeçalho. A primeira linha é a data em que a ANAC gerou o arquivo (`Atualizado em:
2026-10-28`), e o cabeçalho vem na segunda. Separador `;`, texto entre aspas, codificação UTF-8 com BOM.

| Coluna | O que é |
|---|---|
| `ICAO Empresa Aérea` | a empresa, no código ICAO de três letras (`TAM`, `AZU`, `GLO`) |
| `Número Voo` | o número do voo; pode ter letra (`Z9610`) |
| `Código Autorização (DI)` | o tipo de autorização do voo; `0` é o voo regular previsto no planejamento da empresa |
| `Código Tipo Linha` | `N` nacional, `I` internacional, `G` e `C` para as outras naturezas de operação |
| `ICAO Aeródromo Origem`, `ICAO Aeródromo Destino` | os aeroportos, no código ICAO de quatro letras (`SBGR`, `SBGL`) |
| `Partida Prevista`, `Chegada Prevista` | o horário planejado. Vazio (`null`) nos voos fora do planejamento. Alguns vêm com a fração `.100000000` |
| `Partida Real`, `Chegada Real` | o horário em que aconteceu. `null` nos voos cancelados |
| `Situação Voo` | `REALIZADO` ou `CANCELADO` |
| `Código Justificativa` | `N/A` em todas as linhas de 2026 |

Números do recorte, com julho, a primeira entrega de agosto e setembro:

| | Linhas |
|---|---|
| total | 257.667 |
| com partida prevista | 250.506 |
| sem partida prevista (`null`) | 7.161 |
| repetições de empresa + número + partida prevista | 10 (9 linhas idênticas e 1 voo com duas situações) |
| voos que aparecem em dois arquivos | 1 (o GLO 9610 de 01/08, nos arquivos de julho e de agosto) |

Cada arquivo traz alguns voos com partida prevista no começo do mês seguinte: o de setembro tem 20 voos de outubro.

### A primeira entrega de agosto (simulada)

A ANAC gera de novo todos os arquivos do ano a cada publicação, e a linha `Atualizado em` muda junto. O curso
precisa de duas versões do mesmo mês para mostrar uma republicação, e a versão antiga de agosto não está
arquivada. Por isso `vra/VRA_20268.csv` é **simulado**: é o agosto atual da ANAC sem os voos de 30 e 31/08
(5.680 linhas a menos, 82.333 no total) e com `Atualizado em: 2026-09-28`. O `vra_republicado/` traz o agosto
como a ANAC publica hoje, com 88.013 linhas.

### Outubro

O arquivo de outubro de 2026 (`VRA_202610.csv`) entra na aula 3, porque é o mês em que o Galeão e o aeroporto de
Caxias do Sul trocam de administrador. A ANAC publica cada mês perto do dia 28 do mês seguinte: rode
`python scripts/preparar_dados.py` depois da publicação para baixar o arquivo.

## `cadastros/aerodromos/`: os aeródromos públicos

A lista de aeródromos públicos da ANAC, em duas datas. Uma linha por aeródromo. A primeira linha é
`Atualizado em`, o separador é `;` e a codificação é **Windows-1252**, diferente dos outros arquivos.

| Arquivo | Linhas | Colunas | De onde veio |
|---|---|---|---|
| `AerodromosPublicos_2025-04-15.csv` | 501 | 28 (com as pistas) | cópia do Internet Archive, de 18/04/2025 |
| `AerodromosPublicos_2026-11-15.csv` | 496 | 18 | ANAC, baixado em 17/11/2026 |

As colunas que o curso usa: `Código OACI`, `CIAD` (o código do cadastro na ANAC), `Nome`, `Município`, `UF` (o
nome do estado por extenso), `LATGEOPOINT` e `LONGEOPOINT` (coordenadas em graus decimais), `Altitude` (em metros,
com vírgula decimal: `754,0`) e `Situação` (`Cadastrado` ou `Interditado`).

Entre as duas datas, 492 aeródromos aparecem nas duas listas, 9 saem e 4 entram. Mudanças que o curso usa:

| Aeródromo | Coluna | Abril de 2025 | Novembro de 2026 |
|---|---|---|---|
| SBCG | `Nome` | CAMPO GRANDE | Aeroporto Internacional de Campo Grande - Ueze Elias Zahran |
| SBSR | `Nome` | Professor Eriberto Manoel Reino | Professor Eribelto Manoel Reino |
| SBIH | `Município` | ITAITUBA | AVEIRO |
| 11 aeródromos | `Altitude` | | variação de 1 a 11 metros |
| 5 aeródromos | `Situação` | | entre `Cadastrado` e `Interditado` |

## `cadastros/aeroportos_exterior/`

Os 139 aeroportos do exterior que aparecem nos voos de julho a setembro, com nome, cidade, país e continente.
Tirados do OurAirports pelo `scripts/preparar_dados.py`. Três códigos dos voos não estão no OurAirports: `GSAI`,
`GVPR` e `SEQU`.

## `cadastros/empresas/`

As empresas aéreas autorizadas pela ANAC, em dois arquivos com as mesmas colunas: `ICAO`, `Estrangeira` (o código
IATA, apesar do nome), `Razao` (razão social), `Servico`, `Cidade`, `UF`, `Data` e `Ativa`. A primeira linha é
`Atualizado em`, separador `;`, UTF-8 com BOM.

| Arquivo | Linhas | Observação |
|---|---|---|
| `pda_empresas_aereas_nacionais.csv` | 729 | só 20 têm código ICAO; as outras são táxi aéreo e aviação agrícola |
| `pda_empresas_aereas_estrangeiros.csv` | 145 | |

Duas empresas dos voos não estão em nenhum dos dois cadastros: `RUC` (24 voos) e `CHG` (1 voo).

## `cadastros/concessoes/`

Os contratos de concessão de aeroportos da ANAC: 19 contratos, com concessionária, data de assinatura e data de
eficácia (o início da operação pela concessionária). Nas concessões em bloco, o campo `OBJETO` junta todos os
aeroportos do bloco num texto só, às vezes com o código colado na UF anterior (`Aracajú/SESBKG Campina Grande`).

O arquivo tem um erro: o contrato de Aviação Geral traz `SBRJ - Jacarepaguá/RJ`. SBRJ é o código do Santos Dumont;
o de Jacarepaguá é SBJR, como aparece na
[página de aeroportos concedidos da ANAC](https://www.gov.br/anac/pt-br/assuntos/concessoes/aeroportos-concedidos).
O arquivo fica como a ANAC publica; o cadastro de administradores usa SBJR.

## `cadastros/administradores/`: quem administra cada aeroporto

Um cadastro mantido pela Escala, montado a partir das concessões da ANAC. Uma linha por aeroporto e início de
vigência.

| Coluna | O que é |
|---|---|
| `icao` | o aeroporto |
| `administrador` | a concessionária, `Não concedido` ou o órgão público que administra |
| `tipo_administracao` | `Concessão federal` ou `Pública` |
| `vigente_desde` | desde quando esse administrador responde pelo aeroporto. `1900-01-01` quando a data não é conhecida |
| `fonte` | de onde veio a informação |

| Arquivo | Linhas | O que muda |
|---|---|---|
| `administradores_2026-09-30.csv` | 496 | a situação no fim de setembro |
| `administradores_2026-10-31.csv` | 498 | duas linhas novas, as trocas de outubro |

As trocas de outubro, com a fonte:

- **SBGL, Galeão:** a Aena assume a operação em 06/10/2026, no lugar da RIOgaleão
  ([ANAC](https://www.gov.br/anac/pt-br/noticias/2026/concluida-a-venda-assistida-do-aeroporto-do-galeao)).
  A concessionária continua sendo a Concessionária Aeroporto Rio de Janeiro S.A.: o que muda é quem a controla.
- **SBCX, Caxias do Sul:** a Infraero assume a administração em 09/10/2026, no lugar da Prefeitura
  ([Prefeitura de Caxias do Sul](https://caxias.rs.gov.br/noticias/2026/10/infraero-assume-operacao-do-aeroporto-hugo-cantergiani-nesta-sexta-feira)).

Os aeroportos sem contrato de concessão na ANAC aparecem como `Não concedido`; o cadastro não detalha se a
administração é da Infraero, do estado ou do município, com exceção de Caxias do Sul.

## Fontes

- ANAC, dados abertos: Voo Regular Ativo (VRA), lista de aeródromos públicos, empresas aéreas nacionais e
  estrangeiras e dados gerais das concessões de aeroportos. https://sistemas.anac.gov.br/dadosabertos/
- Internet Archive: a lista de aeródromos públicos de abril de 2025. https://web.archive.org/
- OurAirports, dados em domínio público. https://ourairports.com/data/

Os arquivos da ANAC estão como a agência publica, com exceção da primeira entrega de agosto descrita acima.
`scripts/preparar_dados.py` refaz a pasta inteira a partir das fontes.

Não mude os nomes nem a estrutura das pastas: os notebooks e o pipeline leem os arquivos por esses caminhos.
