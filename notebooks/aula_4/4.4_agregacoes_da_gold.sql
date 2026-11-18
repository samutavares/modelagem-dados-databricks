-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Agregações da gold
-- MAGIC
-- MAGIC ## Task 18: uma tabela agregada para o painel, que continue somando certo
-- MAGIC
-- MAGIC O painel quase nunca olha um voo: olha dia, empresa e aeroporto. Ler a fato inteira a cada filtro custa no SQL
-- MAGIC warehouse do Free Edition, que é um só e do menor tamanho.

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O grão da agregada
-- MAGIC
-- MAGIC > Uma linha é **um dia, uma empresa, um aeroporto de origem (na versão da data) e um tipo de linha**.
-- MAGIC
-- MAGIC Toda agregada é uma fato com grão mais grosso. As regras da task 7 continuam:
-- MAGIC
-- MAGIC | Na fato | Na agregada |
-- MAGIC |---|---|
-- MAGIC | `qtd_*` | soma |
-- MAGIC | `atraso_partida_min` | soma e contagem, separadas: a média sai de `soma / contagem` |
-- MAGIC | percentual | não entra |

-- COMMAND ----------

-- MAGIC %md
-- MAGIC No `gold.py`, a materialized view `gold.agg_voo_dia`. Depois da atualização:

-- COMMAND ----------

SELECT (SELECT count(*) FROM gold.fato_voo) AS linhas_fato,
       (SELECT count(*) FROM gold.agg_voo_dia) AS linhas_agregada;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A agregada tem que bater com a fato

-- COMMAND ----------

SELECT 'fato' AS origem,
       sum(qtd_programado) AS voos,
       round(100 * try_divide(sum(qtd_pontual_partida), sum(qtd_realizado)), 4) AS pct_pontual,
       round(try_divide(sum(atraso_partida_min), count(atraso_partida_min)), 4) AS atraso_medio_min
FROM gold.fato_voo
UNION ALL
SELECT 'agregada',
       sum(qtd_programado),
       round(100 * try_divide(sum(qtd_pontual_partida), sum(qtd_realizado)), 4),
       round(try_divide(sum(soma_atraso_partida_min), sum(qtd_atraso_medido)), 4)
FROM gold.agg_voo_dia;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O erro que a agregada convida

-- COMMAND ----------

SELECT round(avg(try_divide(soma_atraso_partida_min, qtd_atraso_medido)), 4) AS media_das_medias
FROM gold.agg_voo_dia;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC A média das médias trata uma linha com 1 voo igual a uma linha com 80. Por isso a agregada guarda soma e
-- MAGIC contagem, e não a média pronta.
-- MAGIC
-- MAGIC ## O que a agregada perde
-- MAGIC
-- MAGIC Destino, número do voo e horário: perguntas sobre eles voltam para a fato.
-- MAGIC
-- MAGIC ## Resultado da task 18
-- MAGIC
-- MAGIC `gold.agg_voo_dia`, conferida contra a fato.
