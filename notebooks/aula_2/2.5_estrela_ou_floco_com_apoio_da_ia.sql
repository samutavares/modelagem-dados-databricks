-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Estrela ou floco com apoio da IA
-- MAGIC
-- MAGIC ## Task 9: decidir onde ficam os dados de concessão, e defender a decisão com números
-- MAGIC
-- MAGIC O time comercial pediu um filtro novo no painel: **concessionária** e **contrato de concessão** do aeroporto.
-- MAGIC Um contrato cobre um ou vários aeroportos (as concessões em bloco).
-- MAGIC
-- MAGIC | Opção | Desenho |
-- MAGIC |---|---|
-- MAGIC | estrela | as colunas do contrato dentro da `dim_aeroporto` |
-- MAGIC | floco | uma `dim_concessao`, ligada à `dim_aeroporto` |

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %python
-- MAGIC import os, shutil
-- MAGIC
-- MAGIC PROJETO = os.path.abspath("../../data")
-- MAGIC VOLUME = "/Volumes/workspace/bronze/arquivos"
-- MAGIC arquivo = "cadastros/concessoes/Concessoes_Aeroportos.csv"
-- MAGIC os.makedirs(os.path.dirname(f"{VOLUME}/{arquivo}"), exist_ok=True)
-- MAGIC shutil.copy(f"{PROJETO}/{arquivo}", f"{VOLUME}/{arquivo}")

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.concessoes
COMMENT 'Contratos de concessão de aeroportos da ANAC'
AS
SELECT *, _metadata.file_name AS _arquivo
FROM read_files('/Volumes/workspace/bronze/arquivos/cadastros/concessoes/',
                format => 'csv', sep => ';', header => true, skipRows => 1, inferColumnTypes => false);

SELECT CONTRATO_CONCESSAO, OBJETO, NOME_CONCESSIONARIA, DATA_EFICACIA FROM bronze.concessoes;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Primeiro, a decisão sem IA
-- MAGIC
-- MAGIC Os critérios da task 8, aplicados ao caso novo. Preencha antes de seguir:
-- MAGIC
-- MAGIC | Critério | O que os dados dizem | Pende para |
-- MAGIC |---|---|---|
-- MAGIC | quantos contratos e quantos aeroportos por contrato | (consulta abaixo) | |
-- MAGIC | quem consome | o painel e a metric view (aula 5) | |
-- MAGIC | com que frequência o contrato muda | | |
-- MAGIC | o que acontece com aeroporto sem contrato | | |

-- COMMAND ----------

SELECT
  CONTRATO_CONCESSAO,
  size(array_distinct(regexp_extract_all(concat(CONTRATO_CONCESSAO, ' ', OBJETO), '(SB[A-Z]{2})', 1))) AS aeroportos,
  array_distinct(regexp_extract_all(concat(CONTRATO_CONCESSAO, ' ', OBJETO), '(SB[A-Z]{2})', 1))       AS codigos
FROM bronze.concessoes
ORDER BY aeroportos DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Repare no contrato de Aviação Geral: `SBRJ` é o Santos Dumont, mas o texto diz Jacarepaguá, que é `SBJR`.
-- MAGIC Erro do arquivo da ANAC, que a página de aeroportos concedidos da agência confirma.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Depois, o pedido para a IA
-- MAGIC
-- MAGIC No Databricks Assistant, um pedido específico, com o contexto que a IA não tem:
-- MAGIC
-- MAGIC > Tenho uma fato de voos com cerca de 250 mil linhas por trimestre e uma dimensão de aeroportos com cerca de
-- MAGIC > 650 linhas. Preciso incluir 19 contratos de concessão; um contrato cobre de 1 a 11 aeroportos e a maioria dos
-- MAGIC > aeroportos não tem contrato. O consumo é um painel AI/BI e uma metric view no Unity Catalog. Eu decidi colocar
-- MAGIC > as colunas do contrato dentro da dimensão de aeroporto. Quais argumentos contra essa decisão eu deveria
-- MAGIC > considerar?
-- MAGIC
-- MAGIC O pedido traz a decisão já tomada e pede o contra-argumento. A IA revisa a decisão, não decide por nós.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Conferindo a resposta nos dados
-- MAGIC
-- MAGIC Cada argumento da resposta vira uma verificação. Exemplos de afirmação comum e como conferir:
-- MAGIC
-- MAGIC | Afirmação | Como conferir |
-- MAGIC |---|---|
-- MAGIC | "o floco economiza armazenamento" | o tamanho medido na task 8 |
-- MAGIC | "a estrela repete o nome da concessionária" | quantas linhas repetem, consulta abaixo |
-- MAGIC | "o join a mais deixa a consulta lenta" | o tempo das duas consultas da task 8 no Query Profile |

-- COMMAND ----------

SELECT NOME_CONCESSIONARIA,
       size(array_distinct(regexp_extract_all(concat(CONTRATO_CONCESSAO, ' ', OBJETO), '(SB[A-Z]{2})', 1))) AS linhas_repetidas_na_estrela
FROM bronze.concessoes
ORDER BY linhas_repetidas_na_estrela DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A decisão do projeto
-- MAGIC
-- MAGIC | Camada | Desenho | Por quê |
-- MAGIC |---|---|---|
-- MAGIC | silver | um aeroporto por linha, com o contrato (normalizado, aula 3) | é onde o dado é corrigido |
-- MAGIC | gold | as colunas na `dim_aeroporto` (estrela) | quem consome é o painel; o floco ganharia kilobytes e custaria um join a mais em toda consulta |
-- MAGIC
-- MAGIC ## Resultado da task 9
-- MAGIC
-- MAGIC A decisão registrada, com os números que a sustentam e o que foi conferido da resposta da IA.
-- MAGIC
-- MAGIC ## Demanda da aula 2 atendida
-- MAGIC
-- MAGIC | Task | Entrega |
-- MAGIC |---|---|
-- MAGIC | 5 | o desenho do modelo e a `dim_data` |
-- MAGIC | 6 | `dim_empresa` e `dim_aeroporto`, com chave própria |
-- MAGIC | 7 | `fato_voo`, com medidas aditivas e relações declaradas |
-- MAGIC | 8 | a geografia em floco de neve, medida contra a estrela |
-- MAGIC | 9 | a decisão estrela ou floco para os contratos de concessão |
