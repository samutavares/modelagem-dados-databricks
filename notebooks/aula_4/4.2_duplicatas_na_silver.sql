-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Duplicatas na silver
-- MAGIC
-- MAGIC ## Task 16: receber agosto republicado pela ANAC
-- MAGIC
-- MAGIC A ANAC publicou agosto de novo, com os voos que faltavam. O arquivo novo entra no volume, ao lado do antigo.

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %python
-- MAGIC import os, shutil
-- MAGIC
-- MAGIC PROJETO = os.path.abspath("../../data")
-- MAGIC VOLUME = "/Volumes/workspace/bronze/arquivos"
-- MAGIC shutil.copy(f"{PROJETO}/vra_republicado/VRA_20268_republicado.csv", f"{VOLUME}/vra/VRA_20268_republicado.csv")
-- MAGIC display(dbutils.fs.ls(f"{VOLUME}/vra"))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Agora, uma atualização do pipeline (**Run pipeline**). O Auto Loader lê só o arquivo novo.

-- COMMAND ----------

SELECT _arquivo, count(*) AS linhas FROM bronze.voos_vra GROUP BY ALL ORDER BY _arquivo;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O que o painel mostraria

-- COMMAND ----------

SELECT d.nome_mes,
       sum(f.qtd_programado)                                                         AS voos,
       round(100 * try_divide(sum(f.qtd_pontual_partida), sum(f.qtd_realizado)), 2)  AS pct_pontual_partida
FROM gold.fato_voo f
JOIN gold.dim_data d ON d.sk_data = f.sk_data
GROUP BY d.mes, d.nome_mes
ORDER BY d.mes;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Agosto com o dobro de voos. E a pontualidade quase não mudou: a duplicata copia os voos com a mesma proporção de
-- MAGIC atrasos. Quem olha só o percentual não percebe nada.
-- MAGIC
-- MAGIC ## Onde a duplicata nasceu

-- COMMAND ----------

SELECT count(*) - count(DISTINCT empresa_icao, numero_voo, partida_prevista) AS repetidos_no_grao
FROM silver.voos;

-- COMMAND ----------

SELECT empresa_icao, numero_voo, partida_prevista, count(*) AS vezes, collect_set(_arquivo) AS arquivos
FROM silver.voos
GROUP BY ALL
HAVING count(*) > 1
ORDER BY vezes DESC, partida_prevista
LIMIT 20;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC | Causa | O que aconteceu |
-- MAGIC |---|---|
-- MAGIC | a streaming table | processa cada linha nova uma vez e nunca olha para trás: o agosto antigo continua lá |
-- MAGIC | a regra de desempate que ficou de fora | as 10 repetições do próprio fornecedor voltaram |
-- MAGIC | o grão | ninguém conferiu que a silver continuava uma linha por etapa programada |
-- MAGIC
-- MAGIC A streaming table supõe que o que chegou não muda. O arquivo do VRA muda: a ANAC regera o mês inteiro.
-- MAGIC
-- MAGIC ## Resultado da task 16
-- MAGIC
-- MAGIC O problema medido: em quantas linhas, em que mês e por quê. A correção é a próxima task.
