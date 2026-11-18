-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Painel de pontualidade
-- MAGIC
-- MAGIC ## Task 24: o painel do time comercial, sobre a metric view
-- MAGIC
-- MAGIC | Pergunta do começo do curso | Visual |
-- MAGIC |---|---|
-- MAGIC | qual empresa atrasa menos no Rio? | barras: pontualidade por empresa, com filtro de aeroporto |
-- MAGIC | setembro foi melhor que agosto? | linha: pontualidade por dia |
-- MAGIC | o Galeão mudou com a troca de administrador? | tabela: pontualidade por administrador da origem |
-- MAGIC | quanto cancela? | contador: taxa de cancelamento |

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Montando o painel (AI/BI Dashboard)
-- MAGIC
-- MAGIC 1. **Dashboards > Create dashboard**, nome `Pontualidade dos voos`.
-- MAGIC 2. Aba **Data > Add data source**: a metric view `workspace.gold.metricas_pontualidade`.
-- MAGIC 3. Um segundo dataset, em SQL, para a lista de trocas de administrador (a consulta abaixo).
-- MAGIC 4. Na tela de desenho:
-- MAGIC    - contadores: `Voos programados`, `Pontualidade na partida`, `Taxa de cancelamento`;
-- MAGIC    - linha: `Data` no eixo X, `Pontualidade na partida` no Y;
-- MAGIC    - barras: `Empresa` e `Pontualidade na partida`, ordenadas, com as 10 empresas de mais voos;
-- MAGIC    - tabela: `Administrador da origem`, `Voos programados`, `Pontualidade na partida`;
-- MAGIC    - filtros: `Mês`, `Aeroporto de origem`, `UF de origem`, `Tipo de linha`.
-- MAGIC 5. **Publish**. O painel publicado roda no SQL warehouse do Free Edition, que desliga sozinho quando fica parado.
-- MAGIC
-- MAGIC Os visuais usam as medidas da metric view: nenhum campo calculado no painel. Se a definição mudar, muda num lugar.

-- COMMAND ----------

SELECT aeroporto_icao, nome,
       lag(administrador) OVER (PARTITION BY aeroporto_icao ORDER BY inicio_vigencia) AS administrador_anterior,
       administrador AS administrador_atual,
       inicio_vigencia AS desde
FROM gold.dim_aeroporto
QUALIFY versao_atual
    AND lag(administrador) OVER (PARTITION BY aeroporto_icao ORDER BY inicio_vigencia) IS NOT NULL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Conferindo o painel contra a fonte
-- MAGIC
-- MAGIC Um número do painel, refeito direto da fato: a pontualidade de setembro.

-- COMMAND ----------

SELECT
  (SELECT round(100 * MEASURE(`Pontualidade na partida`), 2)
   FROM gold.metricas_pontualidade WHERE `Mês` = DATE'2026-09-01') AS metric_view,
  (SELECT round(100 * try_divide(sum(qtd_pontual_partida), sum(qtd_realizado)), 2)
   FROM gold.fato_voo WHERE sk_data BETWEEN 20260901 AND 20260930) AS fato;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Para ir além: Genie
-- MAGIC
-- MAGIC Um espaço do Genie sobre a mesma metric view responde perguntas em português ("qual a pontualidade da Azul em
-- MAGIC Confins em setembro?") usando as mesmas medidas. Confira a consulta que o Genie gerou antes de confiar no número.
-- MAGIC
-- MAGIC ## Resultado da task 24
-- MAGIC
-- MAGIC O painel publicado, com os números conferidos contra a fato.
-- MAGIC
-- MAGIC ## Demanda da aula 5 atendida
-- MAGIC
-- MAGIC | Task | Entrega |
-- MAGIC |---|---|
-- MAGIC | 20 | a barreira de grão no pipeline, antes da fato |
-- MAGIC | 21 | os testes do modelo no job mensal |
-- MAGIC | 22 | documentação no código, dicionário, tags e linhagem |
-- MAGIC | 23 | a metric view com a definição oficial de pontualidade |
-- MAGIC | 24 | o painel de pontualidade |
