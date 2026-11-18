# Modelagem de dados no Databricks: do arquivo ao painel

Projeto do curso de modelagem de dados no Databricks da Alura. Você faz parte do time de dados da **Escala Viagens
Corporativas**, uma agência que compra passagens aéreas para empresas clientes, e vai modelar no Databricks os dados
de voos da ANAC para responder perguntas que hoje cada analista responde de um jeito: qual empresa aérea atrasa
menos no Rio, quanto cancela, e se a pontualidade do Galeão mudou depois da troca do administrador do aeroporto.

Este repositório traz os dados e os notebooks do curso. Tudo roda no **Databricks Free Edition**, gratuito.

## O que você vai construir

| Aula | Tema | O que o projeto ganha |
|---|---|---|
| 1 | Do arquivo à granularidade | os arquivos da ANAC num volume do Unity Catalog, a bronze, o grão decidido e provado, e a `silver.voos` |
| 2 | Modelo estrela e floco de neve | `gold.fato_voo` e as dimensões de data, empresa e aeroporto, com chaves, PK e FK, e a comparação com o floco de neve |
| 3 | Histórico com SCD | a `dim_aeroporto` com SCD tipo 0, 1, 2 e 3, e cada voo ligado à versão do aeroporto que valia no dia |
| 4 | A carga que se repete | o modelo num pipeline declarativo (Lakeflow), que recebe um mês republicado sem duplicar, a agregada e o relatório desnormalizado |
| 5 | Qualidade e consumo | a barreira de grão no pipeline, os testes num job, documentação e linhagem, a metric view e o painel de pontualidade |

## Estrutura

```
modelagem-dados-databricks/
├── data/                       os arquivos da ANAC e os cadastros (veja data/README.md)
├── notebooks/                  um notebook por vídeo, de aula_1 a aula_5
├── pipeline/transformations/   o código do pipeline declarativo, a partir da aula 4
├── scripts/preparar_dados.py   como os dados foram baixados e preparados (não precisa rodar)
├── PLANEJAMENTO.md             o planejamento do curso, para a pessoa instrutora
├── .gitignore
└── .gitattributes              mantém as quebras de linha iguais em qualquer sistema
```

A pasta `pipeline/transformations/` está no estado do fim do curso. Na aula 4, o `qualidade.py` e a linha
`CROSS JOIN ... barreira` do `gold.py` ainda não existem: eles entram no vídeo 5.1.

## Pré-requisito: uma conta no Databricks Free Edition

1. Crie a conta em [databricks.com/learn/free-edition](https://www.databricks.com/learn/free-edition). Não pede
   cartão de crédito.
2. O workspace já vem com o catálogo `workspace`, um SQL warehouse e computação serverless. Não há cluster para
   configurar.

## Trazer o projeto para o Databricks

1. No workspace, **Workspace > Create > Git folder**.
2. Cole a URL deste repositório e confirme. Os notebooks, o pipeline e os dados aparecem dentro do workspace.
3. Abra `notebooks/aula_1/1.2_catalogo_volume_e_bronze.sql`. O notebook cria os schemas e o volume e copia os
   arquivos de `data/` para o volume `/Volumes/workspace/bronze/arquivos`.

O Free Edition limita o acesso à internet a partir do código, por isso os dados vêm no repositório e entram pelo
volume, e não por download dentro do notebook.

## Custo e cota

O Free Edition não cobra nada. Em troca, tem limites
([documentação](https://docs.databricks.com/aws/en/getting-started/free-edition-limitations)):

| Limite | O que significa no curso |
|---|---|
| só computação serverless | os notebooks e o pipeline rodam sem cluster; a primeira célula demora alguns segundos para começar |
| um SQL warehouse, tamanho 2X-Small | o painel e a metric view usam esse warehouse; ele desliga sozinho quando fica parado |
| um pipeline ativo de cada tipo | o curso usa um pipeline só, o `pontualidade` |
| até 5 tasks simultâneas num job | o job da aula 5 tem 2 |
| cota diária de uso | se passar, a computação desliga até o dia seguinte; as tabelas continuam lá |

Para não gastar a cota à toa: deixe o pipeline em modo **Triggered** (roda e para), e não deixe painel com
atualização automática em intervalo curto.

## Outubro: o mês da troca de administrador

A aula 3 usa os voos de outubro de 2026, que mostram o Galeão e o aeroporto de Caxias do Sul trocando de
administrador. A ANAC publica o VRA de um mês por volta do dia 28 do mês seguinte. Se `data/vra/VRA_202610.csv`
ainda não estiver no repositório, rode, no seu computador:

```bash
python scripts/preparar_dados.py
```

e faça o commit do arquivo novo. O `data/README.md` explica o que o script faz.

## Se algo der errado

| Sintoma | O que fazer |
|---|---|
| `PATH_NOT_FOUND` ao ler `/Volumes/...` | rode antes as células do 1.2 que criam o volume e copiam os arquivos |
| `TABLE_OR_VIEW_NOT_FOUND` no começo de uma aula | rode os notebooks das aulas anteriores na ordem, ou o 4.1 em diante, que recria tudo pelo pipeline |
| a atualização do pipeline falha na `gold.verificacao_grao` | uma repetição chegou na silver ou nas dimensões: veja qual expectativa falhou no evento da atualização |
| a computação não liga e fala em cota | a cota diária acabou; volte no dia seguinte, nada foi apagado |
| o Git folder não atualiza | no Git folder, use **Pull** para trazer a versão mais nova |

## Dados

A pasta `data/` traz os voos do VRA (Voo Regular Ativo) da ANAC, de julho a outubro de 2026, e os cadastros de
aeródromos, empresas aéreas e concessões. O `data/README.md` descreve cada conjunto, as colunas e o que foi
simulado para o curso.
