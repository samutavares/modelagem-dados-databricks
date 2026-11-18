-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Bloqueando duplicatas
-- MAGIC
-- MAGIC ## Task 20: impedir que uma repetição no grão chegue ao painel, venha de onde vier
-- MAGIC
-- MAGIC A task 17 corrigiu a causa da duplicata de agosto. Mas a próxima pode vir de outro lugar: de um cadastro, de
-- MAGIC uma mudança no código, de um arquivo novo do fornecedor.

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A chave primária bloqueia?
-- MAGIC
-- MAGIC A fato do notebook tinha chave primária na dimensão. Um teste numa tabela de rascunho:

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.rascunho_pk (sk INT NOT NULL, nome STRING, CONSTRAINT pk_rascunho PRIMARY KEY (sk));

INSERT INTO gold.rascunho_pk VALUES (1, 'Galeão'), (1, 'Galeão de novo');

SELECT * FROM gold.rascunho_pk;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Entraram as duas. No Unity Catalog, chave primária e chave estrangeira são **informativas**: documentam o modelo
-- MAGIC e ajudam o otimizador, mas não são conferidas na escrita. `NOT NULL` e `CHECK` são conferidas.

-- COMMAND ----------

DROP TABLE gold.rascunho_pk;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Expectativas no pipeline
-- MAGIC
-- MAGIC | Ação | Python | O que acontece com a linha que viola |
-- MAGIC |---|---|---|
-- MAGIC | avisar | `@dp.expect` | entra, e a violação fica registrada |
-- MAGIC | descartar | `@dp.expect_or_drop` | não entra |
-- MAGIC | falhar | `@dp.expect_or_fail` | a atualização para e as tabelas ficam como estavam |
-- MAGIC
-- MAGIC Expectativa olha uma linha por vez. Repetição no grão é uma propriedade da tabela inteira: o teste vira uma
-- MAGIC tabela de uma linha, com as contagens, e a expectativa olha essa linha. É o `qualidade.py`:
-- MAGIC
-- MAGIC ```python
-- MAGIC @dp.materialized_view(name=f"{C}.gold.verificacao_grao")
-- MAGIC @dp.expect_or_fail("silver_sem_repeticao_no_grao", "silver_linhas = silver_chaves")
-- MAGIC @dp.expect_or_fail("dim_empresa_sem_repeticao_na_chave", "empresa_linhas = empresa_chaves")
-- MAGIC @dp.expect_or_fail("dim_aeroporto_sem_repeticao_na_chave", "aeroporto_linhas = aeroporto_chaves")
-- MAGIC @dp.expect_or_fail("dim_aeroporto_sem_vigencias_sobrepostas", "vigencias_sobrepostas = 0")
-- MAGIC def verificacao_grao(): ...
-- MAGIC ```
-- MAGIC
-- MAGIC ## Por que a barreira fica antes da fato
-- MAGIC
-- MAGIC Quando uma expectativa falha, a atualização para, mas as tabelas que já tinham terminado ficam atualizadas. Uma
-- MAGIC verificação depois da fato chegaria tarde: a fato com a duplicata já estaria gravada. Por isso a barreira confere
-- MAGIC o que pode duplicar a fato (a silver e as dimensões), e a fato passa a depender dela, no `gold.py`:
-- MAGIC
-- MAGIC ```sql
-- MAGIC FROM voos v
-- MAGIC CROSS JOIN (SELECT 1 FROM {C}.gold.verificacao_grao LIMIT 1) AS barreira
-- MAGIC ```
-- MAGIC
-- MAGIC Se a barreira falhar, a fato não é recalculada e o painel continua com os números da atualização anterior.
-- MAGIC
-- MAGIC Na `silver.voos`, três expectativas de aviso, e a tabela `silver.voos_conflitos`, com as chaves que tinham mais
-- MAGIC de uma versão e o que a regra de desempate escolheu.

-- COMMAND ----------

SELECT * FROM gold.verificacao_grao;

-- COMMAND ----------

SELECT empresa_icao, numero_voo, partida_prevista, situacao, partida_real, codigo_di, _arquivo
FROM silver.voos_conflitos
ORDER BY empresa_icao, numero_voo, partida_prevista;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Uma duplicata que vem do cadastro
-- MAGIC
-- MAGIC Alguém incluiu o Galeão no arquivo de aeroportos do exterior. A célula grava esse arquivo no volume:

-- COMMAND ----------

-- MAGIC %python
-- MAGIC caminho = "/Volumes/workspace/bronze/arquivos/cadastros/aeroportos_exterior/inclusao_manual.csv"
-- MAGIC with open(caminho, "w", encoding="utf-8") as f:
-- MAGIC     f.write("icao;nome;cidade;codigo_pais;pais;continente;latitude;longitude\n")
-- MAGIC     f.write("SBGL;Rio de Janeiro-Galeão International Airport;Rio de Janeiro;BR;Brazil;SA;-22.81;-43.25\n")

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Uma atualização do pipeline. A `dim_aeroporto` passa a ter duas linhas com a mesma chave para cada versão do
-- MAGIC Galeão: cada voo do Galeão encontraria duas. A atualização falha na `gold.verificacao_grao`, com a expectativa
-- MAGIC `dim_aeroporto_sem_repeticao_na_chave`, e a `gold.fato_voo` aparece no grafo como não executada.

-- COMMAND ----------

-- MAGIC %python
-- MAGIC dbutils.fs.rm(caminho)

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Arquivo removido; uma nova atualização passa.
-- MAGIC
-- MAGIC ## Onde a regra de qualidade está nos números
-- MAGIC
-- MAGIC A aba de qualidade de dados da `silver.voos` mostra quantas linhas violaram cada expectativa de aviso. A
-- MAGIC `adiantamento_ate_60_min` aponta voos com partida real mais de uma hora antes da prevista.

-- COMMAND ----------

SELECT empresa_icao, numero_voo, partida_prevista, partida_real,
       timestampdiff(MINUTE, partida_prevista, partida_real) AS atraso_min
FROM silver.voos
WHERE partida_real < partida_prevista - INTERVAL 60 MINUTES
ORDER BY atraso_min
LIMIT 10;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC | Regra | Ação | Por quê |
-- MAGIC |---|---|---|
-- MAGIC | repetição no grão | falhar | número errado no painel é pior que número atrasado |
-- MAGIC | adiantamento acima de 60 minutos | avisar | pode ser erro de data na fonte, mas o voo existiu; tirar mudaria o total de voos |
-- MAGIC | realizado sem partida real | avisar | nenhum caso hoje; se aparecer, a pontualidade fica sem o voo |
-- MAGIC
-- MAGIC ## Resultado da task 20
-- MAGIC
-- MAGIC O pipeline para quando o grão quebra, e registra as violações que não justificam parar.
