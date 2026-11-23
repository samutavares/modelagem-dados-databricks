# Planejamento: Modelagem de dados no Databricks

Documento vivo. O que está em aberto fica marcado em **Pontos em aberto**, no fim.

| Campo | Valor |
|---|---|
| Carreira | Engenharia de Dados |
| Nível | Pleno, nível 2 (a confirmar com Rodrigo) |
| Curso | Modelagem de dados no Databricks, ID a definir |
| Pessoa instrutora | Millena ou Samuel (a definir quem grava) |
| Pessoa coordenadora | Rodrigo |
| Prazo de entrega | a definir |
| Ambiente | Databricks Free Edition, do início ao fim |

## Objetivo geral

Ao final do curso, a pessoa estudante modela um conjunto de dados real no Databricks, do arquivo bruto ao painel.
Ela decide e prova o grão, escolhe entre estrela e floco de neve e o tipo de SCD de cada atributo, e justifica cada
escolha com números. Também leva o modelo para uma carga recorrente que aguenta reprocessamento, e protege o
consumo com testes, documentação e uma definição única de métrica.

## Público-alvo e pré-requisitos

Pessoas engenheiras e analistas de dados que já escrevem SQL com joins, agregações e funções de janela e conhecem
a ideia de camadas bronze, silver e gold. Ler PySpark ajuda na aula 4, mas o pipeline é explicado linha a linha.
Não é preciso ter usado Databricks: o vídeo 1.2 cobre catálogo, schema, volume e tabela.

## CPST do curso

**Contexto.** A Escala Viagens Corporativas compra passagens aéreas para empresas clientes. O time comercial usa
pontualidade para negociar: recomendar a empresa aérea que atrasa menos em cada rota, e defender a escolha no
relatório mensal enviado aos clientes. A fonte é pública: o VRA (Voo Regular Ativo), da ANAC, um CSV por mês com
cada voo programado no Brasil, mais os cadastros de aeródromos, empresas e concessões.

**Problema.** Hoje cada analista baixa o CSV e calcula do seu jeito:

- três analistas chegaram a três números de pontualidade para setembro (média de médias diárias, cancelados no
  denominador, chegada em vez de partida);
- a ANAC republica meses com correção, e quem somou o arquivo novo ao antigo dobrou agosto;
- o cadastro de aeroportos é sobrescrito a cada publicação: quando o Galeão trocou de administrador, em outubro de
  2026, a pergunta "a pontualidade mudou com a troca?" ficou sem resposta;
- ninguém sabe de onde vem o número do painel.

**Solução.** Um modelo dimensional no Databricks: bronze fiel aos arquivos, silver no grão decidido (etapa de voo
programada), estrela na gold com histórico do administrador em SCD tipo 2. Tudo roda num pipeline declarativo que
substitui o mês republicado, com barreira de qualidade e testes, uma metric view com a definição oficial de
pontualidade, e o painel por cima dela. Funcionou quando o mesmo número aparece no SQL, na metric view e no painel,
e quando agosto republicado entra sem duplicar.

**O que não resolve.** O motivo do atraso: a coluna de justificativa da ANAC vem como N/A em todas as linhas de
2026. O modelo diz quem atrasa e onde, não por quê. E a definição de pontual (15 minutos, na partida, sobre os
realizados) continua sendo decisão de negócio: o modelo garante que todos usem a mesma.

**Teoria.** Grão e chaves (Kimball), fato e medidas aditivas, semi e não aditivas, dimensão degenerada e
role-playing, estrela e floco de neve, SCD tipo 0 a 3, membro desconhecido e inferido, tabela de streaming e
materialized view, idempotência de carga, expectativas, camada semântica.

## O dado real e os números do curso

Os números abaixo são dos arquivos reais (janela inicial: julho, a primeira entrega de agosto e setembro de 2026).

| Fato | Número |
|---|---|
| linhas na bronze | 257.667 |
| voos programados (com partida prevista) | 250.506; 7.161 linhas sem partida prevista |
| repetições na chave do grão | 10: 9 linhas idênticas e 1 conflito (AZU 9506, 09/07, CANCELADO e REALIZADO) |
| voo que aparece em dois arquivos | GLO 9610 de 01/08, nos arquivos de julho e de agosto |
| cancelamento | 3,31% |
| pontualidade na partida (até 15 min) | 81,67%; atraso acima de 30 min 9,61%, acima de 60 min 3,95% |
| pontualidade por empresa | TAM 77,77%, AZU 86,29%, GLO 85,63% |
| Galeão (SBGL) | 14.948 partidas, 86,62% pontuais |
| empresas no VRA | 91; RUC (24 voos) e CHG (1) sem cadastro |
| aeroportos sem cadastro | 6, com 488 movimentos |
| agosto somado ao republicado | 165.931 voos em agosto, pontualidade quase igual (81,81%): o erro não aparece na taxa |
| agosto substituído | 85.716 voos; total 255.990; pontualidade 81,63% |

Mudanças reais nos cadastros, usadas na aula 3:

- **Galeão**: passa para a Aena em 06/10/2026
  ([ANAC](https://www.gov.br/anac/pt-br/noticias/2026/concluida-a-venda-assistida-do-aeroporto-do-galeao)).
- **Caxias do Sul**: passa para a Infraero em 09/10/2026
  ([Prefeitura](https://caxias.rs.gov.br/noticias/2026/10/infraero-assume-operacao-do-aeroporto-hugo-cantergiani-nesta-sexta-feira)).
- Entre os dois cadastros de aeródromos (2025 e 2026): mudança de nome de SBCG, correção de grafia em SBSR, troca de
  município de SBIH com as mesmas coordenadas, 11 altitudes e 5 situações.

**Simulado e declarado:** a primeira entrega de agosto é o arquivo real sem os dias 30 e 31 e com o cabeçalho
"Atualizado em: 2026-09-28". O arquivo real faz o papel do republicado. O `data/README.md` documenta isso.

## Quadro de tarefas

Cada vídeo de conteúdo abre com uma task: o problema e o critério de pronto ficam na primeira célula do notebook.

| Task | Vídeo | Problema | Pronto quando |
|---|---|---|---|
| 1 | 1.2 | os arquivos estão fora do Databricks | bronze com todas as linhas, como texto, com arquivo de origem |
| 2 | 1.3 | ninguém sabe o que cada coluna guarda | perfil de cada código e dos formatos de data |
| 3 | 1.4 | não está claro o que é uma linha | grão escolhido e provado com `count(DISTINCT)` |
| 4 | 1.5 | a bronze tem texto, nulos falsos e repetição | `silver.voos` tipada, no grão, com regra de desempate |
| 5 | 2.1 | as perguntas do comercial não têm modelo | desenho da estrela e `dim_data` |
| 6 | 2.2 | código natural muda e vem nulo | dimensões com chave própria, membro desconhecido e inferido |
| 7 | 2.3 | média de média dá número errado | `fato_voo` com medidas aditivas e FKs |
| 8 | 2.4 | a geografia se repete na dimensão | floco montado e medido contra a estrela |
| 9 | 2.5 | onde ficam os dados de concessão | decisão defendida com números, IA conferida |
| 10 | 3.1 | o cadastro novo sobrescreve o antigo | MERGE com tipo 0 e tipo 1 |
| 11 | 3.2 | a troca de administrador apaga o passado | SCD tipo 2 feito à mão com MERGE |
| 12 | 3.3 | o voo aponta para a versão errada | fato ligada à versão pela vigência |
| 13 | 3.4 | o painel quer atual e anterior lado a lado | tipo 3 montado e comparado com o tipo 2 |
| 14 | 3.5 | cada atributo pede um tipo de SCD | decisão por atributo, IA conferida nos dados |
| 15 | 4.1 | a carga depende de rodar notebook à mão | pipeline declarativo com AUTO CDC no SCD 2 |
| 16 | 4.2 | agosto republicado chegou | duplicata reproduzida e causa explicada |
| 17 | 4.3 | o mês novo precisa substituir o antigo | silver como materialized view da última entrega |
| 18 | 4.4 | o painel lê a fato inteira | `agg_voo_dia` conciliada com a fato |
| 19 | 4.5 | o cliente quer uma planilha plana | tabela desnormalizada derivada da estrela |
| 20 | 5.1 | repetição pode chegar por outro caminho | barreira com `expect_or_fail` antes da fato |
| 21 | 5.2 | ninguém confere o modelo depois da carga | notebook de testes num job mensal |
| 22 | 5.3 | ninguém sabe de onde vem o número | comentários no código, dicionário, tags, linhagem |
| 23 | 5.4 | três definições de pontualidade | metric view com a definição oficial |
| 24 | 5.5 | o comercial precisa ver | painel publicado e conferido contra a fato |

## Uso de IA

Dentro da regra da skill: a IA nunca decide o que é conteúdo do curso. O aluno decide primeiro, pede ajuda pontual,
e valida nos dados.

| Momento | O aluno decide antes | Pede para a IA | Valida com |
|---|---|---|---|
| 2.5 | estrela ou floco para a concessão | os prós e contras com os números que ele trouxe | contagem de aeroportos por contrato e tamanho das tabelas |
| 3.5 | o tipo de SCD de cada atributo | revisão da tabela de decisões | consultas nos dois cadastros (SBIH, situação, empresas "EX-") |
| 5.3 (atividade) | nada: é o exercício de achar o erro | comentários das colunas da `agg_voo_dia` | consulta que mostra o comentário errado (`qtd_atraso_medido`) |

**Risco a levar para o Rodrigo:** a ementa tem dois vídeos com "com apoio da IA" no título (2.5 e 3.5), e a skill
diz "sem vídeo dedicado a IA". O desenho trata os dois como vídeos de decisão com dado real, em que a IA é um
passo de revisão. Se o título for lido como vídeo sobre IA, sugerimos trocar para "Estrela ou floco: decidindo com
números" e "Escolhendo o SCD de cada atributo".

## Aula 1: Do arquivo à granularidade

**Problema da aula:** os arquivos da ANAC chegam com texto em tudo, linha de cabeçalho extra, nulo escrito como
`'null'` e voo repetido. Ninguém definiu o que é uma linha.

Objetivos de aprendizagem:

- Implementar a ingestão de arquivos num volume do Unity Catalog para uma tabela bronze que preserva o dado como
  veio.
- Analisar o conteúdo de cada coluna antes de decidir tipo e regra.
- Justificar o grão de uma tabela de fatos provando a unicidade da chave com os dados.
- Implementar a silver no grão decidido, com regra de desempate explícita para conflitos.

| Vídeo | Título | Competências e habilidades |
|---|---|---|
| 1.1 | Apresentação | contextualizar o cenário da Escala e o problema dos três números |
| 1.2 | Catálogo, volume e bronze | organizar catálogo, schema e volume; ler CSV com `read_files` e contrato de colunas |
| 1.3 | Explorando os dados de voos | perfilar códigos, formatos de data e nulos falsos |
| 1.4 | Definindo a granularidade | testar chaves candidatas e justificar o grão |
| 1.5 | Limpando os voos na silver | tipar, desempatar com `row_number` e conferir a silver |

Roteiro por tópicos:

- **1.1** Apresentação e autodescrição. O que já sabemos (SQL, camadas) e onde estamos na carreira. A Escala, as
  três perguntas do comercial, os três números de setembro. O que vamos construir, aula por aula, e o ambiente
  (Free Edition, sem custo, com cota).
- **1.2** Catálogo `workspace`, schemas bronze, silver e gold, volume. Upload de um arquivo pela interface e cópia
  dos demais pelo notebook. Primeira leitura com `read_files`, que bate na parede (a linha "Atualizado em" vira
  cabeçalho). O cabeçalho real (`Número Voo`) não é o nome do contrato: `header => false` e `skipRows => 2`,
  schema explícito em texto, `_metadata` para arquivo e horário. Custo e cota.
- **1.3** Perfil de cada código (DI, tipo de linha, situação), o `'null'` em texto, a fração `.100000000` nos
  horários, mês por arquivo (voo de um mês no arquivo do outro).
- **1.4** Chaves candidatas, contagem distinta, as 10 repetições, o conflito AZU 9506. Decisão: etapa de voo
  programada (empresa, número do voo e partida prevista). As 7.161 linhas sem partida prevista ficam fora do grão.
- **1.5** View tipada, `row_number` com REALIZADO primeiro e menor atraso absoluto, `silver.voos` e
  `silver.voos_sem_partida_prevista`. Conferência: linhas iguais a chaves. Pontualidade por mês como primeiro
  número confiável.

Atividades: múltipla escolha sobre grão; "faça como eu fiz" da silver; dissertativa: por que não usar
`SELECT DISTINCT` para limpar as repetições.

## Aula 2: Modelo estrela e floco de neve

**Problema da aula:** a silver é uma lista de voos. Responder "qual empresa atrasa menos no Rio" exige juntar
cadastros com códigos que mudam, vêm nulos ou não existem, e calcular taxas sem cair na média de médias.

Objetivos de aprendizagem:

- Elaborar um modelo estrela a partir das perguntas de negócio.
- Implementar dimensões com chave substituta, membro desconhecido e membro inferido.
- Implementar uma fato com medidas aditivas e justificar por que a taxa é calculada na consulta.
- Comparar estrela e floco de neve com medidas de tamanho e de consulta, e recomendar um para a gold.

| Vídeo | Título | Competências e habilidades |
|---|---|---|
| 2.1 | O modelo estrela | decompor as perguntas em fato e dimensões; `dim_data` |
| 2.2 | Dimensões e chaves | chave substituta com `xxhash64`, membro -1 e inferido, PK informativa |
| 2.3 | Fato e medidas | medidas 0/1 aditivas, dimensão degenerada, role-playing, FK e diagrama |
| 2.4 | O modelo floco de neve | normalizar a geografia e medir a diferença |
| 2.5 | Estrela ou floco com apoio da IA | decidir a concessão com números e conferir a revisão da IA |

Roteiro por tópicos:

- **2.1** As perguntas viram desenho: o que se mede (voo) e por onde se corta (data, empresa, aeroporto). Grão da
  fato herdado da silver. `dim_data` com feriados e chave aaaammdd.
- **2.2** Por que não usar o código ICAO como chave (muda, vem nulo, falta no cadastro). `xxhash64` em vez de
  identity, porque a tabela é recriada. `xxhash64(NULL)` não é nulo: o `CASE`. Membro -1, inferidos (RUC, CHG e os
  6 aeroportos). PK no Unity Catalog é informativa.
- **2.3** Fato com `qtd_*` 0/1, atraso em minutos, origem e destino na mesma dimensão (role-playing), número do voo
  como degenerada. FK e o diagrama no Catalog Explorer. Demonstração: média das pontualidades diárias contra a
  razão das somas. A pergunta do Rio respondida.
- **2.4** `floco_dim_aeroporto`, `floco_dim_municipio`, `floco_dim_uf`. A mesma consulta nos dois modelos, tamanho
  com `DESCRIBE DETAIL`, quantos joins. Onde o floco ganha e onde perde.
- **2.5** O dado de concessão (contrato com vários aeroportos). O aluno decide e escreve o motivo, depois pede a
  revisão ao Assistant e confere os números que ele cita. Decisão: estrela na gold.

Atividades: múltipla escolha sobre medida aditiva; dissertativa: quando o floco compensa; mão na massa: adicionar
a dimensão de tipo de linha.

## Aula 3: Histórico com SCD

**Problema da aula:** chega o cadastro novo de aeródromos e o de administradores de outubro. Sobrescrever apaga a
informação de que o Galeão era do RIOgaleão até 05/10, e a pergunta de negócio depende dela.

Objetivos de aprendizagem:

- Implementar SCD tipo 0 e 1 com MERGE, justificando o tipo de cada atributo.
- Implementar SCD tipo 2 manualmente e explicar o papel da vigência e da versão atual.
- Implementar o join da fato com a versão da dimensão pela data do evento, e analisar o erro de usar a versão atual.
- Comparar SCD tipo 2 e tipo 3 e recomendar o tipo para cada atributo com base nas mudanças reais.

| Vídeo | Título | Competências e habilidades |
|---|---|---|
| 3.1 | SCD tipo 0 e 1 | comparar cadastros, MERGE com sobrescrita e valor original, time travel não é histórico |
| 3.2 | SCD tipo 2 | vigência, versão atual, MERGE que fecha e abre versão |
| 3.3 | Fato e versão da dimensão | join por intervalo de vigência, o erro do `versao_atual` |
| 3.4 | SCD tipo 3 | coluna de valor anterior e comparação com o tipo 2 |
| 3.5 | Escolhendo o SCD com apoio da IA | decidir por atributo e conferir a revisão da IA nos dados |

Roteiro por tópicos:

- **3.1** Diferença entre os dois cadastros (SBCG, SBSR, SBIH, altitudes, situação). Tipo 1 para correções, tipo 0
  para `ciad` e `nome_original`. MERGE. `DESCRIBE HISTORY`: time travel guarda versões da tabela, não da regra de
  negócio, e expira.
- **3.2** Administradores de setembro, depois de outubro. A dimensão ganha `inicio_vigencia`, `fim_vigencia`,
  `versao_atual` e a chave passa a ser aeroporto e início. O MERGE que insere cada mudança duas vezes (fecha e
  abre). Rodar de novo não pode duplicar.
- **3.3** VRA de outubro. A fato reconstruída com o join por vigência. Galeão por administrador. O mesmo cálculo
  com `versao_atual = true` atribui setembro à Aena.
- **3.4** `administrador_anterior`. A mesma lista tirada do tipo 2 com `lag`. Tipo 3 guarda uma troca; o tipo 2
  guarda todas.
- **3.5** Tabela de decisão por atributo feita pelo aluno, revisão pedida à IA, conferência nos dados (SBIH mudou
  de município com as mesmas coordenadas, então é correção e tipo 1). Erros comuns da IA.

Atividades: múltipla escolha sobre tipos de SCD; "faça como eu fiz" do MERGE tipo 2; dissertativa: por que time
travel não substitui SCD.

## Aula 4: A carga que se repete

**Problema da aula:** a carga é uma sequência de notebooks rodados à mão. No mês seguinte a ANAC republica agosto,
e a carga incremental soma o arquivo novo ao antigo.

Objetivos de aprendizagem:

- Implementar o modelo num pipeline declarativo, escolhendo entre tabela de streaming e materialized view para
  cada tabela.
- Analisar a causa de duplicatas numa carga incremental.
- Implementar o reprocessamento de um mês corrigido de forma idempotente.
- Implementar uma agregada que preserva a aditividade das medidas.
- Avaliar quando desnormalizar e justificar a tabela derivada.

| Vídeo | Título | Competências e habilidades |
|---|---|---|
| 4.1 | Do notebook ao pipeline declarativo | tabela de streaming e materialized view, Auto Loader, AUTO CDC no SCD 2 |
| 4.2 | Duplicatas na silver | reproduzir e explicar a duplicata do mês republicado |
| 4.3 | Reprocessando o mês corrigido | silver como última entrega de cada mês, full refresh |
| 4.4 | Agregações da gold | agregada no grão do painel, conciliada com a fato |
| 4.5 | Quando desnormalizar | tabela plana para o cliente, derivada da estrela |

Roteiro por tópicos:

- **4.1** O mesmo modelo em `pipeline/transformations/`. Streaming para o que só chega (bronze), materialized view
  para o que se recalcula. O SCD 2 feito à mão na aula 3 vira `create_auto_cdc_flow`, com a mesma vigência.
- **4.2** O republicado entra no volume, o pipeline roda, agosto dobra. A pontualidade quase não muda (81,81%):
  o erro passa despercebido no indicador. Causa: o streaming processa cada arquivo novo uma vez e não sabe que
  ele substitui outro.
- **4.3** Opções (apagar e recarregar, MERGE por mês, materialized view da última entrega). A silver vira
  materialized view com a última entrega de cada mês e o mesmo desempate. Full refresh. Agosto com 85.716 voos.
- **4.4** `agg_voo_dia` com somas e contagem, nunca taxa. Conciliação com a fato. O atraso médio refeito como soma
  sobre contagem.
- **4.5** O relatório do cliente como tabela plana derivada da estrela. Comparação no Query Profile e tamanho.
  Critérios: quem consome, com que frequência, e a estrela continua sendo a fonte.

Atividades: múltipla escolha sobre streaming e materialized view; dissertativa: por que a taxa não vai na agregada;
mão na massa: simular a republicação de setembro.

## Aula 5: Qualidade e consumo

**Problema da aula:** o modelo funciona, mas nada impede que uma repetição chegue ao painel por outro caminho,
ninguém confere o modelo depois da carga, e a pontualidade ainda é calculada de três jeitos.

Objetivos de aprendizagem:

- Implementar expectativas no pipeline e justificar onde a barreira precisa ficar para proteger o consumo.
- Elaborar testes do modelo dimensional e agendá-los após a carga.
- Elaborar a documentação do modelo no código e analisar a linhagem.
- Implementar uma metric view com a definição oficial de cada indicador.
- Elaborar um painel sobre a metric view e conferir os números contra a fonte.

| Vídeo | Título | Competências e habilidades |
|---|---|---|
| 5.1 | Bloqueando duplicatas | PK não bloqueia; `expect`, `expect_or_drop`, `expect_or_fail`; barreira antes da fato |
| 5.2 | Testando a granularidade | testes de grão, FK, membro desconhecido e vigência; job mensal |
| 5.3 | Documentação e linhagem | comentários no código, `information_schema`, tags, linhagem; atividade de IA |
| 5.4 | Metric view de pontualidade | YAML com joins, dimensões e medidas; `MEASURE()` |
| 5.5 | Painel de pontualidade | AI/BI Dashboard sobre a metric view, conferência, Genie |
| 5.6 | Conclusão | retomar o problema, o que foi resolvido e o que ficou de fora |

Roteiro por tópicos:

- **5.1** Inserir uma linha repetida numa tabela com PK: entra. Os três tipos de expectativa. Repetição é
  propriedade da tabela, por isso o teste vira uma tabela de uma linha. Uma expectativa que falha não desfaz o que
  já foi gravado, então a barreira fica antes da fato e a fato depende dela. Um cadastro com o Galeão duplicado
  faz a atualização falhar e a fato não é recalculada.
- **5.2** O notebook de testes com `assert`. O job mensal: atualização do pipeline e depois os testes, com
  notificação por e-mail.
- **5.3** Comentários no `comment=` e no `schema=` do pipeline, o dicionário pelo `information_schema`, tags nos
  schemas, a linhagem de tabela e de coluna. Atividade de achar o erro nos comentários gerados pela IA.
- **5.4** Os três números de setembro lado a lado. A metric view em YAML: fonte, joins, dimensões, medidas com
  `try_divide`. Consultas com `MEASURE()`. O Galeão por administrador sem escrever o join de vigência.
- **5.5** O painel: contadores, linha por dia, barras por empresa, tabela por administrador, filtros. Publicação.
  Um número conferido contra a fato. Genie como extensão.
- **5.6** Os três números viraram um. Agosto republicado entra sem duplicar. A troca do Galeão tem resposta. O que
  ficou de fora: o motivo do atraso (justificativa N/A), a definição de pontual como decisão de negócio, e
  streaming de verdade (o VRA é mensal).

Atividades: múltipla escolha sobre expectativas; dissertativa: por que a PK informativa não basta; atividade de IA
do 5.3; "o que aprendemos" do curso.

## Nomes dos arquivos de vídeo

Formato `ID-videoX.Y-alura-Nome do vídeo`. Com o ID a definir, por exemplo:

```
ID-video1.1-alura-Apresentação
ID-video1.2-alura-Catálogo, volume e bronze
ID-video1.3-alura-Explorando os dados de voos
ID-video1.4-alura-Definindo a granularidade
ID-video1.5-alura-Limpando os voos na silver
ID-video2.1-alura-O modelo estrela
ID-video2.2-alura-Dimensões e chaves
ID-video2.3-alura-Fato e medidas
ID-video2.4-alura-O modelo floco de neve
ID-video2.5-alura-Estrela ou floco com apoio da IA
ID-video3.1-alura-SCD tipo 0 e 1
ID-video3.2-alura-SCD tipo 2
ID-video3.3-alura-Fato e versão da dimensão
ID-video3.4-alura-SCD tipo 3
ID-video3.5-alura-Escolhendo o SCD com apoio da IA
ID-video4.1-alura-Do notebook ao pipeline declarativo
ID-video4.2-alura-Duplicatas na silver
ID-video4.3-alura-Reprocessando o mês corrigido
ID-video4.4-alura-Agregações da gold
ID-video4.5-alura-Quando desnormalizar
ID-video5.1-alura-Bloqueando duplicatas
ID-video5.2-alura-Testando a granularidade
ID-video5.3-alura-Documentação e linhagem
ID-video5.4-alura-Metric view de pontualidade
ID-video5.5-alura-Painel de pontualidade
ID-video5.6-alura-Conclusão
```

## Pontos em aberto e riscos

- **Outubro ainda não publicado.** O VRA de outubro de 2026 sai por volta de 28/11. Sem ele, a aula 3 não mostra
  a troca do Galeão nos voos. Rodar `python scripts/preparar_dados.py` quando sair, e refazer os números do 3.3 em
  diante.
- **Código não executado no Databricks.** Os notebooks e o pipeline foram escritos sem rodar no workspace. Os
  números desta página vêm dos arquivos, calculados fora do Databricks. Testar tudo antes de gravar, em especial:
  - `read_files` do VRA com `header => false` e `skipRows => 2` (com `header => true` o schema casa pelo nome e `numero_voo` nasce nula);
  - trocar a `silver.voos` de tabela de streaming para materialized view no mesmo pipeline (pode exigir apagar a
    tabela ou full refresh);
  - `except_column_list` do AUTO CDC junto com a coluna de sequência;
  - a inferência de dependências do pipeline nas consultas em `spark.sql`, incluindo a barreira da fato;
  - o nome da tela do diagrama de entidades no Catalog Explorer e a geração de comentários por IA;
  - tabelas de sistema (`system.access.table_lineage`) no Free Edition.
- **Agosto simulado.** A primeira entrega de agosto foi construída a partir do arquivo real. Está declarado no
  `data/README.md` e precisa ser dito no vídeo 4.2.
- **Vídeos com IA no título.** Ver a seção de uso de IA.
- **Nível.** Pleno pela profundidade (SCD, idempotência, camada semântica). Confirmar com o Rodrigo.

## Fontes

- [Limites do Databricks Free Edition](https://docs.databricks.com/aws/en/getting-started/free-edition-limitations)
- [Lakeflow Declarative Pipelines](https://docs.databricks.com/aws/en/dlt/)
- [AUTO CDC e SCD tipo 2](https://docs.databricks.com/aws/en/dlt/cdc)
- [Expectativas](https://docs.databricks.com/aws/en/dlt/expectations)
- [Metric views](https://docs.databricks.com/aws/en/metric-views/)
- [Constraints no Unity Catalog](https://docs.databricks.com/aws/en/tables/constraints)
- [Dados abertos da ANAC: VRA](https://www.gov.br/anac/pt-br/acesso-a-informacao/dados-abertos)
- [OurAirports, domínio público](https://ourairports.com/data/)
- Kimball, R.; Ross, M. *The Data Warehouse Toolkit*, 3ª ed. Wiley, 2013.
