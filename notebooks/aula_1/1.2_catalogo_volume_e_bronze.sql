-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Catálogo, volume e bronze
-- MAGIC
-- MAGIC ## Task 1: trazer os arquivos da ANAC para dentro do Databricks, sem perder nada do que veio
-- MAGIC
-- MAGIC | Camada | O que guarda | Quem lê |
-- MAGIC |---|---|---|
-- MAGIC | volume | o arquivo como chegou | só a carga |
-- MAGIC | bronze | o arquivo em tabela, tudo como texto | a limpeza |
-- MAGIC | silver | o dado limpo, com tipo e grão definido | o modelo |
-- MAGIC | gold | o modelo dimensional | analytics e o painel |

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O endereço de uma tabela no Unity Catalog
-- MAGIC
-- MAGIC `catálogo.schema.tabela`. No Free Edition, o catálogo `workspace` já existe.

-- COMMAND ----------

USE CATALOG workspace;

CREATE SCHEMA IF NOT EXISTS bronze COMMENT 'Arquivos da ANAC em tabela, como chegaram';
CREATE SCHEMA IF NOT EXISTS silver COMMENT 'Dados limpos, com tipo e grão definido';
CREATE SCHEMA IF NOT EXISTS gold COMMENT 'Modelo dimensional de pontualidade';

SHOW SCHEMAS;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O volume: uma pasta governada para arquivos
-- MAGIC
-- MAGIC O Free Edition só acessa um conjunto restrito de domínios na internet: o notebook não baixa da ANAC.
-- MAGIC Os arquivos entram pelo volume.

-- COMMAND ----------

CREATE VOLUME IF NOT EXISTS bronze.arquivos COMMENT 'Arquivos recebidos da ANAC e dos cadastros';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Um arquivo pela interface: **Catalog > workspace > bronze > arquivos > Upload to this volume**, com
-- MAGIC `data/vra/VRA_20267.csv` numa pasta `vra`. Os outros, pela célula abaixo, que copia da pasta do projeto
-- MAGIC (o Git folder) para o volume.

-- COMMAND ----------

-- MAGIC %python
-- MAGIC import os, shutil
-- MAGIC
-- MAGIC PROJETO = os.path.abspath("../../data")
-- MAGIC VOLUME = "/Volumes/workspace/bronze/arquivos"
-- MAGIC
-- MAGIC for arquivo in ["vra/VRA_20268.csv", "vra/VRA_20269.csv"]:
-- MAGIC     os.makedirs(os.path.dirname(f"{VOLUME}/{arquivo}"), exist_ok=True)
-- MAGIC     shutil.copy(f"{PROJETO}/{arquivo}", f"{VOLUME}/{arquivo}")
-- MAGIC
-- MAGIC display(dbutils.fs.ls(f"{VOLUME}/vra"))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Primeira leitura

-- COMMAND ----------

SELECT *
FROM read_files('/Volumes/workspace/bronze/arquivos/vra/', format => 'csv', sep => ';', header => true)
LIMIT 5;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Uma coluna só, chamada `Atualizado em: 2026-10-28`. A primeira linha do arquivo não é o cabeçalho.

-- COMMAND ----------

SELECT *
FROM read_files('/Volumes/workspace/bronze/arquivos/vra/', format => 'csv', sep => ';', header => true,
                skipRows => 1)
LIMIT 5;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O contrato da bronze
-- MAGIC
-- MAGIC - nomes sem acento, espaço nem parêntese, declarados pelo projeto;
-- MAGIC - tudo como texto: a bronze guarda o que veio, mesmo o que não converte;
-- MAGIC - de onde e quando a linha chegou: `_arquivo` e `_recebido_em`.
-- MAGIC
-- MAGIC O cabeçalho do arquivo é `Número Voo`, não `numero_voo`. Com `header => true` o `read_files` casa pelo
-- MAGIC nome e a coluna nasce nula. A carga ignora o cabeçalho e pula as duas primeiras linhas.

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.voos_vra
COMMENT 'Voos do VRA da ANAC, linha a linha, como chegaram'
AS
SELECT
  *,
  _metadata.file_name AS _arquivo,
  _metadata.file_modification_time AS _recebido_em
FROM read_files(
  '/Volumes/workspace/bronze/arquivos/vra/',
  format => 'csv', sep => ';', header => false, skipRows => 2,
  schema => 'icao_empresa STRING, numero_voo STRING, codigo_di STRING, codigo_tipo_linha STRING,
             icao_origem STRING, icao_destino STRING, partida_prevista STRING, partida_real STRING,
             chegada_prevista STRING, chegada_real STRING, situacao_voo STRING, codigo_justificativa STRING'
);

-- COMMAND ----------

SELECT _arquivo, count(*) AS linhas, min(_recebido_em) AS recebido_em
FROM bronze.voos_vra
GROUP BY _arquivo
ORDER BY _arquivo;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Resultado da task 1
-- MAGIC
-- MAGIC Três meses de voos na `bronze.voos_vra`, com o arquivo de origem de cada linha.
-- MAGIC
-- MAGIC ## Custo
-- MAGIC
-- MAGIC O Free Edition não cobra, mas tem cota diária de uso. Se a cota acabar, o compute para até o dia
-- MAGIC seguinte, sem apagar dados. O compute serverless do notebook desliga sozinho quando fica parado.
