-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Metric view de pontualidade
-- MAGIC
-- MAGIC ## Task 23: uma definição única de pontualidade, que o painel, o SQL e o Genie usam igual
-- MAGIC
-- MAGIC O problema do começo do curso: três analistas, três números de pontualidade para o mesmo mês.
-- MAGIC
-- MAGIC | Analista | Calculou |
-- MAGIC |---|---|
-- MAGIC | 1 | média da pontualidade de cada dia |
-- MAGIC | 2 | cancelados no denominador |
-- MAGIC | 3 | chegada em vez de partida |

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

SELECT
  round(100 * avg(pontualidade_dia), 2) AS analista_1,
  (SELECT round(100 * try_divide(sum(qtd_pontual_partida), sum(qtd_programado)), 2)
   FROM gold.fato_voo WHERE sk_data BETWEEN 20260901 AND 20260930) AS analista_2,
  (SELECT round(100 * try_divide(sum(qtd_pontual_chegada), sum(qtd_realizado)), 2)
   FROM gold.fato_voo WHERE sk_data BETWEEN 20260901 AND 20260930) AS analista_3
FROM (
  SELECT try_divide(sum(qtd_pontual_partida), sum(qtd_realizado)) AS pontualidade_dia
  FROM gold.fato_voo
  WHERE sk_data BETWEEN 20260901 AND 20260930
  GROUP BY sk_data
);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A metric view
-- MAGIC
-- MAGIC Uma view do Unity Catalog que declara, em YAML:
-- MAGIC
-- MAGIC - a fonte e os joins do modelo estrela, uma vez;
-- MAGIC - as **dimensões** (`fields`): por onde dá para cortar;
-- MAGIC - as **medidas** (`measures`): a fórmula de cada indicador, calculada no nível que a consulta pedir.
-- MAGIC
-- MAGIC A pontualidade é uma razão: a metric view guarda a fórmula, não o resultado, e recalcula para qualquer corte.

-- COMMAND ----------

CREATE OR REPLACE VIEW gold.metricas_pontualidade
WITH METRICS
LANGUAGE YAML
COMMENT 'Pontualidade dos voos programados no Brasil, a partir do VRA da ANAC. Definição oficial da Escala.'
AS $$
version: 1.1
comment: "Pontualidade dos voos programados. Pontual: partida real até 15 minutos depois da prevista, sobre os voos realizados."
source: workspace.gold.fato_voo

joins:
  - name: data
    source: workspace.gold.dim_data
    'on': source.sk_data = data.sk_data
  - name: empresa
    source: workspace.gold.dim_empresa
    'on': source.sk_empresa = empresa.sk_empresa
  - name: origem
    source: workspace.gold.dim_aeroporto
    'on': source.sk_aeroporto_origem = origem.sk_aeroporto
  - name: destino
    source: workspace.gold.dim_aeroporto
    'on': source.sk_aeroporto_destino = destino.sk_aeroporto

fields:
  - name: Data
    expr: data.data
  - name: Mês
    expr: data.inicio_mes
  - name: Dia da semana
    expr: data.nome_dia_semana
  - name: Empresa
    expr: coalesce(empresa.empresa_iata, empresa.empresa_icao) || ' - ' || empresa.razao_social
  - name: Nacionalidade da empresa
    expr: empresa.nacionalidade
  - name: Aeroporto de origem
    expr: origem.aeroporto_icao || ' - ' || origem.nome
  - name: UF de origem
    expr: origem.uf
  - name: Região de origem
    expr: origem.regiao
  - name: Administrador da origem
    expr: origem.administrador
  - name: Aeroporto de destino
    expr: destino.aeroporto_icao || ' - ' || destino.nome
  - name: Tipo de linha
    expr: CASE source.tipo_linha WHEN 'N' THEN 'Nacional' WHEN 'I' THEN 'Internacional' ELSE 'Outras' END

measures:
  - name: Voos programados
    expr: SUM(source.qtd_programado)
  - name: Voos realizados
    expr: SUM(source.qtd_realizado)
  - name: Voos cancelados
    expr: SUM(source.qtd_cancelado)
  - name: Taxa de cancelamento
    expr: try_divide(SUM(source.qtd_cancelado), SUM(source.qtd_programado))
  - name: Pontualidade na partida
    expr: try_divide(SUM(source.qtd_pontual_partida), SUM(source.qtd_realizado))
  - name: Pontualidade na chegada
    expr: try_divide(SUM(source.qtd_pontual_chegada), SUM(source.qtd_realizado))
  - name: Atrasos acima de 30 minutos
    expr: try_divide(SUM(source.qtd_atraso_30), SUM(source.qtd_realizado))
  - name: Atrasos acima de 60 minutos
    expr: try_divide(SUM(source.qtd_atraso_60), SUM(source.qtd_realizado))
  - name: Atraso médio na partida (min)
    expr: AVG(source.atraso_partida_min)
$$;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Consultando
-- MAGIC
-- MAGIC Medida se pede com `MEASURE()`. O agrupamento escolhe o corte; a fórmula é sempre a mesma.

-- COMMAND ----------

SELECT `Mês`,
       MEASURE(`Voos programados`)                    AS voos,
       round(100 * MEASURE(`Pontualidade na partida`), 2) AS pct_pontual_partida,
       round(100 * MEASURE(`Taxa de cancelamento`), 2)    AS pct_cancelado
FROM gold.metricas_pontualidade
GROUP BY ALL
ORDER BY `Mês`;

-- COMMAND ----------

SELECT `Administrador da origem`,
       MEASURE(`Voos programados`)                        AS voos,
       round(100 * MEASURE(`Pontualidade na partida`), 2) AS pct_pontual_partida
FROM gold.metricas_pontualidade
WHERE `Aeroporto de origem` LIKE 'SBGL%'
GROUP BY ALL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC O mesmo resultado da task 12, sem escrever o join pela vigência: a fato já aponta para a versão certa, e a
-- MAGIC metric view só declara o join pela chave.
-- MAGIC
-- MAGIC ## O que a metric view não resolve
-- MAGIC
-- MAGIC A definição de "pontual" (15 minutos, partida, sobre realizados) é uma decisão de negócio. A metric view garante
-- MAGIC que todos usem a mesma; não garante que ela seja a certa para cada cliente. Pontualidade na chegada fica
-- MAGIC disponível para quem precisar.
-- MAGIC
-- MAGIC ## Resultado da task 23
-- MAGIC
-- MAGIC `gold.metricas_pontualidade`: uma definição de cada indicador, consultável em SQL e pronta para o painel.
