-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Explorando os dados de voos
-- MAGIC
-- MAGIC ## Task 2: descobrir o que cada coluna guarda antes de decidir qualquer coisa
-- MAGIC
-- MAGIC Perguntas que o time comercial vai fazer: quantos voos, quantos cancelados, quanto atrasou. Para cada uma,
-- MAGIC qual coluna responde, e em que formato ela chega?

-- COMMAND ----------

USE CATALOG workspace;

SELECT * FROM bronze.voos_vra LIMIT 10;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## As colunas de código

-- COMMAND ----------

SELECT situacao_voo, count(*) AS linhas FROM bronze.voos_vra GROUP BY ALL ORDER BY linhas DESC;

-- COMMAND ----------

SELECT codigo_tipo_linha, count(*) AS linhas FROM bronze.voos_vra GROUP BY ALL ORDER BY linhas DESC;

-- COMMAND ----------

SELECT codigo_di, count(*) AS linhas FROM bronze.voos_vra GROUP BY ALL ORDER BY linhas DESC;

-- COMMAND ----------

SELECT codigo_justificativa, count(*) AS linhas FROM bronze.voos_vra GROUP BY ALL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Os horários
-- MAGIC
-- MAGIC Texto. Três formatos aparecem: o horário com segundos, o horário com a fração `.100000000` e a palavra `null`.

-- COMMAND ----------

SELECT
  CASE
    WHEN partida_prevista = 'null' THEN 'texto null'
    WHEN length(partida_prevista) > 19 THEN 'com fração'
    ELSE 'horário'
  END AS formato,
  count(*) AS linhas,
  min(partida_prevista) AS exemplo
FROM bronze.voos_vra
GROUP BY ALL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Quem não tem partida prevista? O cruzamento com o tipo de autorização (`codigo_di`):

-- COMMAND ----------

SELECT codigo_di,
       count_if(partida_prevista = 'null') AS sem_partida_prevista,
       count_if(partida_prevista <> 'null') AS com_partida_prevista
FROM bronze.voos_vra
GROUP BY ALL
ORDER BY sem_partida_prevista DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC E o `null` da partida real acompanha a situação?

-- COMMAND ----------

SELECT situacao_voo, partida_real = 'null' AS partida_real_vazia, count(*) AS linhas
FROM bronze.voos_vra
GROUP BY ALL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Um arquivo é um mês?

-- COMMAND ----------

SELECT _arquivo,
       left(partida_prevista, 7) AS mes_partida_prevista,
       count(*) AS linhas
FROM bronze.voos_vra
WHERE partida_prevista <> 'null'
GROUP BY ALL
ORDER BY _arquivo, mes_partida_prevista;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O que a exploração deixou para decidir
-- MAGIC
-- MAGIC | Achado | Decisão que pede |
-- MAGIC |---|---|
-- MAGIC | horário em texto, com `null` e com fração | conversão na silver |
-- MAGIC | voos sem partida prevista | entram na conta de pontualidade? |
-- MAGIC | justificativa sempre `N/A` | a causa do atraso fica fora do projeto |
-- MAGIC | voos do mês seguinte em cada arquivo | o mês do voo vem da partida prevista, não do arquivo |
-- MAGIC | o que identifica um voo? | o grão, na próxima task |
