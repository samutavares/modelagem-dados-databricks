-- Databricks notebook source
-- MAGIC %md
-- MAGIC # SCD tipo 3
-- MAGIC
-- MAGIC ## Task 13: mostrar no painel o administrador atual e o anterior, lado a lado
-- MAGIC
-- MAGIC O time comercial quer uma lista de aeroportos que trocaram de administrador, com o nome antigo e o novo na
-- MAGIC mesma linha. Com o tipo 2, isso é uma consulta com janela. Com o tipo 3, é uma coluna.
-- MAGIC
-- MAGIC | Tipo 3 | |
-- MAGIC |---|---|
-- MAGIC | uma mudança | o valor atual vai para a coluna "anterior" e o novo ocupa a coluna atual |
-- MAGIC | linhas | uma por aeroporto, como no tipo 1 |
-- MAGIC | histórico | só um passo para trás |

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A tabela tipo 3, a partir da entrega de setembro

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.aeroporto_administrador_tipo3
COMMENT 'Administrador atual e anterior de cada aeroporto (SCD tipo 3)'
AS
SELECT icao AS aeroporto_icao,
       administrador          AS administrador_atual,
       CAST(NULL AS STRING)   AS administrador_anterior,
       to_date(vigente_desde) AS administrador_desde
FROM bronze.administradores
WHERE _arquivo = 'administradores_2026-09-30.csv';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A entrega de outubro no tipo 3
-- MAGIC
-- MAGIC No `UPDATE SET`, todas as expressões usam os valores de antes do comando: `administrador_anterior` recebe o
-- MAGIC atual antigo, não o novo.

-- COMMAND ----------

MERGE INTO gold.aeroporto_administrador_tipo3 t
USING (
  SELECT icao, administrador, to_date(vigente_desde) AS vigente_desde
  FROM bronze.administradores
  WHERE _arquivo = 'administradores_2026-10-31.csv'
) n
ON t.aeroporto_icao = n.icao AND n.vigente_desde > t.administrador_desde
WHEN MATCHED AND n.administrador <> t.administrador_atual THEN UPDATE SET
  administrador_anterior = t.administrador_atual,
  administrador_atual    = n.administrador,
  administrador_desde    = n.vigente_desde;

-- COMMAND ----------

SELECT * FROM gold.aeroporto_administrador_tipo3 WHERE administrador_anterior IS NOT NULL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A mesma lista a partir do tipo 2

-- COMMAND ----------

SELECT aeroporto_icao,
       lag(administrador) OVER (PARTITION BY aeroporto_icao ORDER BY inicio_vigencia) AS administrador_anterior,
       administrador AS administrador_atual,
       inicio_vigencia AS administrador_desde
FROM gold.dim_aeroporto
QUALIFY versao_atual
    AND lag(administrador) OVER (PARTITION BY aeroporto_icao ORDER BY inicio_vigencia) IS NOT NULL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O limite do tipo 3
-- MAGIC
-- MAGIC Se a Aena deixar o Galeão em 2030, a coluna "anterior" passa a ser Aena e a RIOgaleão some. E um voo de
-- MAGIC setembro, ligado pelo ICAO, enxerga o administrador atual, não o da data dele.
-- MAGIC
-- MAGIC | Pergunta | Tipo 2 | Tipo 3 |
-- MAGIC |---|---|---|
-- MAGIC | quem administrava no dia do voo? | sim | não |
-- MAGIC | qual era o administrador anterior? | com janela | uma coluna |
-- MAGIC | e o anterior do anterior? | sim | não |
-- MAGIC | linhas por aeroporto | uma por versão | uma |
-- MAGIC
-- MAGIC No projeto, o tipo 2 fica na dimensão. A lista do painel sai do tipo 2 com `lag`; a tabela tipo 3 serve de
-- MAGIC comparação e pode ser apagada.

-- COMMAND ----------

DROP TABLE gold.aeroporto_administrador_tipo3;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Resultado da task 13
-- MAGIC
-- MAGIC A lista de trocas de administrador para o painel, e o tipo 3 avaliado contra o tipo 2.
