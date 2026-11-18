-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Limpando os voos na silver
-- MAGIC
-- MAGIC ## Task 4: gravar os voos no grão decidido, com tipo e sem repetição
-- MAGIC
-- MAGIC | Da bronze | Para a silver |
-- MAGIC |---|---|
-- MAGIC | `'null'` | `NULL` |
-- MAGIC | horário em texto, com ou sem fração | `TIMESTAMP` |
-- MAGIC | códigos `N`, `I`, `G`, `C` | mantidos, com a descrição na dimensão (aula 2) |
-- MAGIC | linhas repetidas na chave | uma por etapa programada |
-- MAGIC | sem partida prevista | `silver.voos_sem_partida_prevista` |

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Convertendo os horários
-- MAGIC
-- MAGIC Os 19 primeiros caracteres são sempre `aaaa-mm-dd hh:mm:ss`: cortar antes de converter elimina a fração.

-- COMMAND ----------

SELECT partida_prevista,
       to_timestamp(left(nullif(partida_prevista, 'null'), 19)) AS convertida
FROM bronze.voos_vra
WHERE partida_prevista LIKE '%.1%' OR partida_prevista = 'null'
LIMIT 6;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A view tipada
-- MAGIC
-- MAGIC Uma view temporária com os tipos, reaproveitada pelas duas tabelas da silver.

-- COMMAND ----------

CREATE OR REPLACE TEMPORARY VIEW voos_tipados AS
SELECT
  icao_empresa                                                  AS empresa_icao,
  numero_voo,
  codigo_di,
  codigo_tipo_linha                                             AS tipo_linha,
  icao_origem                                                   AS origem_icao,
  icao_destino                                                  AS destino_icao,
  to_timestamp(left(nullif(partida_prevista, 'null'), 19))      AS partida_prevista,
  to_timestamp(left(nullif(partida_real, 'null'), 19))          AS partida_real,
  to_timestamp(left(nullif(chegada_prevista, 'null'), 19))      AS chegada_prevista,
  to_timestamp(left(nullif(chegada_real, 'null'), 19))          AS chegada_real,
  situacao_voo                                                  AS situacao,
  make_date(int(regexp_extract(_arquivo, 'VRA_([0-9]{4})([0-9]{1,2})', 1)),
            int(regexp_extract(_arquivo, 'VRA_([0-9]{4})([0-9]{1,2})', 2)), 1) AS mes_arquivo,
  _arquivo,
  _recebido_em
FROM bronze.voos_vra;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Uma linha por etapa programada
-- MAGIC
-- MAGIC `row_number` numera as linhas de cada chave na ordem da regra; fica a de número 1.
-- MAGIC
-- MAGIC 1. `REALIZADO` antes de `CANCELADO`;
-- MAGIC 2. entre duas realizadas, a de partida real mais próxima da prevista.

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.voos
COMMENT 'Etapas de voo programadas: uma linha por empresa, número de voo e partida prevista'
AS
SELECT * EXCEPT (ordem)
FROM (
  SELECT *,
         row_number() OVER (
           PARTITION BY empresa_icao, numero_voo, partida_prevista
           ORDER BY situacao = 'REALIZADO' DESC,
                    abs(timestampdiff(MINUTE, partida_prevista, partida_real)) ASC NULLS LAST
         ) AS ordem
  FROM voos_tipados
  WHERE partida_prevista IS NOT NULL
)
WHERE ordem = 1;

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.voos_sem_partida_prevista
COMMENT 'Voos sem partida prevista: fora do grão de etapa programada'
AS
SELECT * FROM voos_tipados WHERE partida_prevista IS NULL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Conferindo

-- COMMAND ----------

SELECT
  (SELECT count(*) FROM bronze.voos_vra)                   AS bronze,
  (SELECT count(*) FROM silver.voos)                       AS silver_voos,
  (SELECT count(*) FROM silver.voos_sem_partida_prevista)  AS silver_sem_partida,
  (SELECT count(*) - count(DISTINCT empresa_icao, numero_voo, partida_prevista) FROM silver.voos) AS repetidos_no_grao;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Uma primeira resposta

-- COMMAND ----------

SELECT
  date_trunc('MONTH', partida_prevista)                               AS mes,
  count(*)                                                            AS voos_programados,
  count_if(situacao = 'CANCELADO')                                    AS cancelados,
  round(100 * try_divide(count_if(timestampdiff(MINUTE, partida_prevista, partida_real) <= 15),
                         count_if(situacao = 'REALIZADO')), 2)        AS pct_pontual_partida
FROM silver.voos
GROUP BY ALL
ORDER BY mes;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Demanda da aula 1 atendida
-- MAGIC
-- MAGIC | Task | Entrega |
-- MAGIC |---|---|
-- MAGIC | 1 | catálogo, schemas, volume e `bronze.voos_vra` |
-- MAGIC | 2 | o que cada coluna guarda e o que precisa ser decidido |
-- MAGIC | 3 | o grão: uma etapa de voo programada, provado nos dados |
-- MAGIC | 4 | `silver.voos` no grão e `silver.voos_sem_partida_prevista` |
-- MAGIC
-- MAGIC Para responder "qual empresa atrasa menos no Rio", a silver ainda não basta: não tem o nome da empresa nem a
-- MAGIC cidade do aeroporto. É o modelo da aula 2.
