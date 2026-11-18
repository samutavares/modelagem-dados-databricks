-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Do notebook ao pipeline declarativo
-- MAGIC
-- MAGIC ## Task 15: levar a carga para um pipeline que roda sozinho todo mês
-- MAGIC
-- MAGIC Hoje a carga é uma sequência de notebooks rodados na mão, na ordem certa. Todo mês chega um arquivo da ANAC.
-- MAGIC
-- MAGIC | Notebook | Pipeline declarativo (Lakeflow) |
-- MAGIC |---|---|
-- MAGIC | a gente diz **como** e **em que ordem** | a gente diz **o que** cada tabela é; o pipeline descobre a ordem |
-- MAGIC | `CREATE OR REPLACE` relê tudo | streaming table lê só o que é novo |
-- MAGIC | a qualidade é conferida depois | expectativas registradas a cada atualização |

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Os dois tipos de tabela do pipeline
-- MAGIC
-- MAGIC | Tipo | Como atualiza | Serve para |
-- MAGIC |---|---|---|
-- MAGIC | streaming table | processa só as linhas novas da fonte, uma vez | arquivos que chegam e não mudam |
-- MAGIC | materialized view | o resultado sempre reflete a consulta sobre a fonte inteira | o que depende de olhar tudo: janela, join com dimensão, agregação |
-- MAGIC
-- MAGIC | Tabela | Tipo |
-- MAGIC |---|---|
-- MAGIC | `bronze.voos_vra`, `bronze.administradores` | streaming table, com Auto Loader lendo o volume |
-- MAGIC | `bronze.aerodromos`, `bronze.empresas`, `bronze.aeroportos_exterior` | materialized view: cadastros pequenos, relidos inteiros |
-- MAGIC | `silver.voos` | streaming table: só o mês novo é processado |
-- MAGIC | `silver.administradores_historico` | AUTO CDC com SCD tipo 2: o MERGE da task 11, feito pelo pipeline |
-- MAGIC | gold | materialized views |

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O pipeline passa a ser o dono das tabelas
-- MAGIC
-- MAGIC Uma tabela criada por notebook não pode ser assumida pelo pipeline. A célula abaixo já vem pronta: apaga as
-- MAGIC tabelas das aulas anteriores. O volume e os arquivos continuam.

-- COMMAND ----------

DROP TABLE IF EXISTS gold.fato_voo;
DROP TABLE IF EXISTS gold.dim_aeroporto;
DROP TABLE IF EXISTS gold.dim_empresa;
DROP TABLE IF EXISTS gold.dim_data;
DROP TABLE IF EXISTS gold.floco_dim_aeroporto;
DROP TABLE IF EXISTS gold.floco_dim_municipio;
DROP TABLE IF EXISTS gold.floco_dim_uf;
DROP TABLE IF EXISTS silver.voos;
DROP TABLE IF EXISTS silver.voos_sem_partida_prevista;
DROP TABLE IF EXISTS silver.ref_uf;
DROP TABLE IF EXISTS bronze.voos_vra;
DROP TABLE IF EXISTS bronze.aerodromos;
DROP TABLE IF EXISTS bronze.empresas;
DROP TABLE IF EXISTS bronze.aeroportos_exterior;
DROP TABLE IF EXISTS bronze.administradores;
DROP TABLE IF EXISTS bronze.concessoes;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Criando o pipeline
-- MAGIC
-- MAGIC 1. **Jobs & Pipelines > Create > ETL pipeline**.
-- MAGIC 2. Nome: `pontualidade`. Catálogo `workspace`, schema padrão `silver`.
-- MAGIC 3. Em **Settings > Configuration**, a chave `catalogo` com o valor `workspace`.
-- MAGIC 4. Pasta do código: a pasta `pipeline/transformations` do projeto, no Git folder.
-- MAGIC 5. Modo **Triggered**: roda quando mandado e desliga. O Free Edition permite um pipeline ativo por tipo.
-- MAGIC
-- MAGIC Nesta task, o `silver.py` começa com a versão abaixo, a migração direta da task 4 para streaming. A versão do
-- MAGIC projeto, com as mudanças das tasks 17 e 21, está no repositório.
-- MAGIC
-- MAGIC ```python
-- MAGIC @dp.table(name=f"{CATALOGO}.silver.voos",
-- MAGIC           comment="Etapas de voo programadas: uma linha por empresa, número de voo e partida prevista")
-- MAGIC def voos():
-- MAGIC     return (
-- MAGIC         spark.readStream.table(f"{CATALOGO}.bronze.voos_vra")
-- MAGIC         .select(...)                      # as mesmas colunas da task 4
-- MAGIC         .filter("partida_prevista IS NOT NULL")
-- MAGIC     )
-- MAGIC ```
-- MAGIC
-- MAGIC A regra de desempate da task 4 usa janela (`row_number`), que não roda numa streaming table. Ela fica de fora
-- MAGIC por enquanto.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Depois da primeira atualização
-- MAGIC
-- MAGIC - o grafo mostra a ordem que o pipeline descobriu, da bronze à fato;
-- MAGIC - cada tabela mostra quantas linhas escreveu;
-- MAGIC - o AUTO CDC preencheu `__START_AT` e `__END_AT` com a vigência do cadastro.

-- COMMAND ----------

SELECT icao, administrador, __START_AT, __END_AT
FROM silver.administradores_historico
WHERE icao IN ('SBGL', 'SBCX')
ORDER BY icao, __START_AT;

-- COMMAND ----------

SELECT
  (SELECT count(*) FROM bronze.voos_vra) AS bronze,
  (SELECT count(*) FROM silver.voos)     AS silver,
  (SELECT count(*) FROM gold.fato_voo)   AS fato;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Resultado da task 15
-- MAGIC
-- MAGIC A carga inteira num pipeline: um clique, ou um agendamento, refaz da bronze à fato na ordem certa.
