-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Fato e medidas
-- MAGIC
-- MAGIC ## Task 7: montar a fato de voos com medidas que podem ser somadas sem erro
-- MAGIC
-- MAGIC | Tipo de medida | Exemplo | Pode somar? |
-- MAGIC |---|---|---|
-- MAGIC | aditiva | voos programados, cancelados, minutos de atraso | por qualquer dimensão |
-- MAGIC | semiaditiva | frota disponível no dia | por algumas dimensões, nunca pelo tempo |
-- MAGIC | não aditiva | percentual de pontualidade | nunca: recalcula a partir das aditivas |

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A fato
-- MAGIC
-- MAGIC - as chaves das dimensões, com `-1` quando o join não encontra par;
-- MAGIC - o número do voo, a situação e os horários ficam na fato: são do voo, não de uma dimensão (dimensão degenerada);
-- MAGIC - os indicadores de situação viram `0` ou `1`, para a soma contar.

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.fato_voo
COMMENT 'Voos: uma linha por etapa de voo programada (empresa, número do voo e partida prevista)'
AS
WITH voos AS (
  SELECT *,
         timestampdiff(MINUTE, partida_prevista, partida_real) AS atraso_partida_min,
         timestampdiff(MINUTE, chegada_prevista, chegada_real) AS atraso_chegada_min
  FROM silver.voos
)
SELECT
  int(date_format(v.partida_prevista, 'yyyyMMdd'))       AS sk_data,
  coalesce(e.sk_empresa, -1)                             AS sk_empresa,
  coalesce(o.sk_aeroporto, -1)                           AS sk_aeroporto_origem,
  coalesce(d.sk_aeroporto, -1)                           AS sk_aeroporto_destino,
  v.numero_voo,
  v.codigo_di,
  v.tipo_linha,
  v.situacao,
  v.partida_prevista,
  v.partida_real,
  v.chegada_prevista,
  v.chegada_real,
  1                                                      AS qtd_programado,
  int(v.situacao = 'REALIZADO')                          AS qtd_realizado,
  int(v.situacao = 'CANCELADO')                          AS qtd_cancelado,
  v.atraso_partida_min,
  v.atraso_chegada_min,
  int(coalesce(v.atraso_partida_min <= 15, false))       AS qtd_pontual_partida,
  int(coalesce(v.atraso_chegada_min <= 15, false))       AS qtd_pontual_chegada,
  int(coalesce(v.atraso_partida_min > 30, false))        AS qtd_atraso_30,
  int(coalesce(v.atraso_partida_min > 60, false))        AS qtd_atraso_60
FROM voos v
LEFT JOIN gold.dim_empresa e   ON e.empresa_icao = v.empresa_icao
LEFT JOIN gold.dim_aeroporto o ON o.aeroporto_icao = v.origem_icao
LEFT JOIN gold.dim_aeroporto d ON d.aeroporto_icao = v.destino_icao;

-- COMMAND ----------

SELECT count(*) AS linhas_fato, (SELECT count(*) FROM silver.voos) AS linhas_silver FROM gold.fato_voo;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## As relações no catálogo
-- MAGIC
-- MAGIC Com as chaves estrangeiras declaradas, o Catalog Explorer desenha o modelo: abra `gold.fato_voo` e veja o
-- MAGIC diagrama de relacionamentos.

-- COMMAND ----------

ALTER TABLE gold.fato_voo ADD CONSTRAINT fk_voo_data
  FOREIGN KEY (sk_data) REFERENCES gold.dim_data (sk_data);
ALTER TABLE gold.fato_voo ADD CONSTRAINT fk_voo_empresa
  FOREIGN KEY (sk_empresa) REFERENCES gold.dim_empresa (sk_empresa);
ALTER TABLE gold.fato_voo ADD CONSTRAINT fk_voo_origem
  FOREIGN KEY (sk_aeroporto_origem) REFERENCES gold.dim_aeroporto (sk_aeroporto);
ALTER TABLE gold.fato_voo ADD CONSTRAINT fk_voo_destino
  FOREIGN KEY (sk_aeroporto_destino) REFERENCES gold.dim_aeroporto (sk_aeroporto);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Por que o percentual não fica na fato
-- MAGIC
-- MAGIC A pontualidade de setembro de duas formas: a média das pontualidades de cada dia, e a soma dos pontuais
-- MAGIC dividida pela soma dos realizados.

-- COMMAND ----------

WITH por_dia AS (
  SELECT sk_data,
         try_divide(sum(qtd_pontual_partida), sum(qtd_realizado)) AS pontualidade_dia
  FROM gold.fato_voo
  WHERE sk_data BETWEEN 20260901 AND 20260930
  GROUP BY sk_data
)
SELECT
  round(100 * avg(pontualidade_dia), 2) AS media_das_medias,
  round(100 * (SELECT try_divide(sum(qtd_pontual_partida), sum(qtd_realizado))
               FROM gold.fato_voo WHERE sk_data BETWEEN 20260901 AND 20260930), 2) AS razao_das_somas
FROM por_dia;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC A média das médias dá o mesmo peso a um domingo com poucos voos e a uma sexta lotada. A fato guarda as partes
-- MAGIC (pontuais e realizados) e o percentual é calculado na consulta.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A pergunta do time comercial

-- COMMAND ----------

SELECT
  e.razao_social,
  sum(f.qtd_programado)                                                     AS voos,
  round(100 * try_divide(sum(f.qtd_pontual_partida), sum(f.qtd_realizado)), 1) AS pct_pontual_partida,
  round(100 * try_divide(sum(f.qtd_cancelado), sum(f.qtd_programado)), 1)      AS pct_cancelado
FROM gold.fato_voo f
JOIN gold.dim_empresa e   ON e.sk_empresa = f.sk_empresa
JOIN gold.dim_aeroporto o ON o.sk_aeroporto = f.sk_aeroporto_origem
WHERE o.municipio = 'RIO DE JANEIRO'
GROUP BY ALL
HAVING sum(f.qtd_programado) >= 300
ORDER BY pct_pontual_partida DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Resultado da task 7
-- MAGIC
-- MAGIC `gold.fato_voo` no grão da silver, com medidas aditivas e as relações declaradas.
