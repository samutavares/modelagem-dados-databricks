-- Databricks notebook source
-- MAGIC %md
-- MAGIC # O modelo floco de neve
-- MAGIC
-- MAGIC ## Task 8: normalizar a geografia do aeroporto e medir o que muda
-- MAGIC
-- MAGIC Na `dim_aeroporto`, "Rio de Janeiro, RJ, Sudeste" se repete em todo aeroporto do estado. No floco de neve, cada
-- MAGIC nível da hierarquia vira uma tabela:
-- MAGIC
-- MAGIC ```
-- MAGIC fato_voo -- floco_dim_aeroporto -- floco_dim_municipio -- floco_dim_uf
-- MAGIC ```

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.floco_dim_uf AS
SELECT xxhash64(uf) AS sk_uf, uf, uf_nome, regiao, 'Brasil' AS pais
FROM silver.ref_uf
UNION ALL
SELECT -1, 'EX', 'Exterior', 'Exterior', 'Exterior';

CREATE OR REPLACE TABLE gold.floco_dim_municipio AS
SELECT DISTINCT xxhash64(municipio, coalesce(uf, 'EX')) AS sk_municipio,
       municipio,
       CASE WHEN uf IS NULL THEN -1 ELSE xxhash64(uf) END AS sk_uf
FROM gold.dim_aeroporto
WHERE municipio IS NOT NULL;

CREATE OR REPLACE TABLE gold.floco_dim_aeroporto AS
SELECT sk_aeroporto, aeroporto_icao, nome, latitude, longitude, altitude_m, situacao, fonte_cadastro,
       xxhash64(municipio, coalesce(uf, 'EX')) AS sk_municipio
FROM gold.dim_aeroporto;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A mesma pergunta nos dois modelos
-- MAGIC
-- MAGIC Pontualidade de partida por região de origem.

-- COMMAND ----------

SELECT o.regiao,
       round(100 * try_divide(sum(f.qtd_pontual_partida), sum(f.qtd_realizado)), 2) AS pct_pontual
FROM gold.fato_voo f
JOIN gold.dim_aeroporto o ON o.sk_aeroporto = f.sk_aeroporto_origem
GROUP BY ALL
ORDER BY pct_pontual DESC;

-- COMMAND ----------

SELECT u.regiao,
       round(100 * try_divide(sum(f.qtd_pontual_partida), sum(f.qtd_realizado)), 2) AS pct_pontual
FROM gold.fato_voo f
JOIN gold.floco_dim_aeroporto a  ON a.sk_aeroporto = f.sk_aeroporto_origem
JOIN gold.floco_dim_municipio m  ON m.sk_municipio = a.sk_municipio
JOIN gold.floco_dim_uf u         ON u.sk_uf = m.sk_uf
GROUP BY ALL
ORDER BY pct_pontual DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Os aeroportos inferidos e o desconhecido somem do floco: sem município, não têm par no join. Na estrela, eles
-- MAGIC aparecem com a região `Não informada`.
-- MAGIC
-- MAGIC ## Quanto o floco economiza

-- COMMAND ----------

-- MAGIC %python
-- MAGIC def tamanho(tabelas):
-- MAGIC     return sum(spark.sql(f"DESCRIBE DETAIL {t}").first()["sizeInBytes"] for t in tabelas)
-- MAGIC
-- MAGIC print("estrela:", tamanho(["gold.dim_aeroporto"]), "bytes")
-- MAGIC print("floco:  ", tamanho(["gold.floco_dim_aeroporto", "gold.floco_dim_municipio", "gold.floco_dim_uf"]), "bytes")

-- COMMAND ----------

-- MAGIC %md
-- MAGIC | | Estrela | Floco de neve |
-- MAGIC |---|---|---|
-- MAGIC | joins para chegar na região | 1 | 3 |
-- MAGIC | onde a região é corrigida | em cada aeroporto do estado | numa linha da `floco_dim_uf` |
-- MAGIC | linhas sem par no meio do caminho | aparecem como "Não informada" | somem do resultado se o join for `INNER` |
-- MAGIC | espaço | | a diferença está em kilobytes, numa dimensão de centenas de linhas |
-- MAGIC
-- MAGIC ## Resultado da task 8
-- MAGIC
-- MAGIC A geografia normalizada em três tabelas, e o custo e o ganho medidos nos dados do projeto.
