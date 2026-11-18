-- Databricks notebook source
-- MAGIC %md
-- MAGIC # SCD tipo 0 e 1
-- MAGIC
-- MAGIC ## Task 10: receber o cadastro novo de aeródromos sem recriar a dimensão
-- MAGIC
-- MAGIC A dimensão de aeroporto veio do cadastro de abril de 2025. A ANAC publicou o de novembro de 2026. O que muda,
-- MAGIC e o que a dimensão faz com cada mudança?
-- MAGIC
-- MAGIC SCD (*slowly changing dimension*, dimensão que muda devagar) é a regra de cada atributo quando a fonte muda.

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %python
-- MAGIC import os, shutil
-- MAGIC
-- MAGIC PROJETO = os.path.abspath("../../data")
-- MAGIC VOLUME = "/Volumes/workspace/bronze/arquivos"
-- MAGIC arquivo = "cadastros/aerodromos/AerodromosPublicos_2026-11-15.csv"
-- MAGIC shutil.copy(f"{PROJETO}/{arquivo}", f"{VOLUME}/{arquivo}")

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O cadastro novo na bronze
-- MAGIC
-- MAGIC O arquivo novo tem 18 colunas; o de 2025 tinha 28, com as pistas. Como a bronze escolhe as colunas pelo nome,
-- MAGIC a mesma leitura serve para os dois.

-- COMMAND ----------

INSERT INTO bronze.aerodromos
SELECT
  `Código OACI`, CIAD, Nome, `Município`, UF, LATGEOPOINT, LONGEOPOINT, Altitude, `Situação`,
  to_date(regexp_extract(_metadata.file_name, '([0-9]{4}-[0-9]{2}-[0-9]{2})', 1)),
  _metadata.file_name
FROM read_files('/Volumes/workspace/bronze/arquivos/cadastros/aerodromos/AerodromosPublicos_2026-11-15.csv',
                format => 'csv', sep => ';', header => true, skipRows => 1, encoding => 'windows-1252',
                inferColumnTypes => false);

SELECT data_cadastro, count(*) AS aerodromos FROM bronze.aerodromos GROUP BY ALL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O que mudou entre os dois cadastros

-- COMMAND ----------

WITH antigo AS (SELECT * FROM bronze.aerodromos WHERE data_cadastro = DATE'2025-04-15'),
     novo   AS (SELECT * FROM bronze.aerodromos WHERE data_cadastro = DATE'2026-11-15')
SELECT
  coalesce(a.codigo_oaci, n.codigo_oaci) AS codigo_oaci,
  CASE WHEN a.codigo_oaci IS NULL THEN 'entrou'
       WHEN n.codigo_oaci IS NULL THEN 'saiu'
       ELSE 'mudou' END                  AS tipo,
  a.nome AS nome_antes,           n.nome AS nome_depois,
  a.municipio AS municipio_antes, n.municipio AS municipio_depois,
  a.altitude AS altitude_antes,   n.altitude AS altitude_depois,
  a.situacao AS situacao_antes,   n.situacao AS situacao_depois
FROM antigo a
FULL JOIN novo n ON a.codigo_oaci = n.codigo_oaci
WHERE a.codigo_oaci IS NULL OR n.codigo_oaci IS NULL
   OR NOT (a.nome <=> n.nome AND a.municipio <=> n.municipio AND a.altitude <=> n.altitude
           AND a.situacao <=> n.situacao AND a.latitude <=> n.latitude AND a.longitude <=> n.longitude)
ORDER BY tipo, codigo_oaci;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Uma regra por atributo
-- MAGIC
-- MAGIC | Tipo | Regra | Atributos do projeto |
-- MAGIC |---|---|---|
-- MAGIC | 0 | guarda o primeiro valor conhecido e nunca muda | `ciad`, `nome_original` |
-- MAGIC | 1 | sobrescreve: vale o valor mais recente, sem histórico | `nome`, `municipio`, coordenadas, `altitude_m`, `situacao` |
-- MAGIC
-- MAGIC `nome_original` serve para conciliar com relatórios antigos: é o nome com que o aeroporto entrou no modelo.

-- COMMAND ----------

ALTER TABLE gold.dim_aeroporto ADD COLUMN nome_original STRING AFTER nome;
UPDATE gold.dim_aeroporto SET nome_original = nome WHERE fonte_cadastro = 'ANAC';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O MERGE
-- MAGIC
-- MAGIC | O aeroporto do cadastro novo... | O que acontece |
-- MAGIC |---|---|
-- MAGIC | já está na dimensão e mudou | tipo 1 sobrescreve; tipo 0 só preenche se estava vazio |
-- MAGIC | não está na dimensão | entra |
-- MAGIC
-- MAGIC Os aeroportos inferidos dos voos têm `ciad` e `nome_original` vazios: o cadastro novo completa.

-- COMMAND ----------

CREATE OR REPLACE TEMPORARY VIEW aerodromos_novos AS
SELECT
  a.codigo_oaci AS aeroporto_icao, a.ciad, a.nome, a.municipio, u.uf, u.uf_nome, u.regiao,
  double(a.latitude) AS latitude, double(a.longitude) AS longitude,
  double(replace(a.altitude, ',', '.')) AS altitude_m, a.situacao
FROM bronze.aerodromos a
LEFT JOIN silver.ref_uf u ON a.uf = u.uf_nome
WHERE a.data_cadastro = DATE'2026-11-15';

-- COMMAND ----------

MERGE INTO gold.dim_aeroporto d
USING aerodromos_novos n
ON d.aeroporto_icao = n.aeroporto_icao
WHEN MATCHED AND NOT (d.nome <=> n.nome AND d.municipio <=> n.municipio AND d.latitude <=> n.latitude
                      AND d.longitude <=> n.longitude AND d.altitude_m <=> n.altitude_m
                      AND d.situacao <=> n.situacao AND d.ciad IS NOT NULL) THEN UPDATE SET
  ciad           = coalesce(d.ciad, n.ciad),
  nome_original  = coalesce(d.nome_original, n.nome),
  nome           = n.nome,
  municipio      = n.municipio,
  uf             = n.uf,
  uf_nome        = n.uf_nome,
  regiao         = n.regiao,
  pais           = 'Brasil',
  continente     = 'América do Sul',
  latitude       = n.latitude,
  longitude      = n.longitude,
  altitude_m     = n.altitude_m,
  situacao       = n.situacao,
  fonte_cadastro = 'ANAC'
WHEN NOT MATCHED THEN INSERT
  (sk_aeroporto, aeroporto_icao, ciad, nome, nome_original, municipio, uf, uf_nome, regiao, pais, continente,
   latitude, longitude, altitude_m, situacao, fonte_cadastro)
VALUES
  (xxhash64(n.aeroporto_icao), n.aeroporto_icao, n.ciad, n.nome, n.nome, n.municipio, n.uf, n.uf_nome, n.regiao,
   'Brasil', 'América do Sul', n.latitude, n.longitude, n.altitude_m, n.situacao, 'ANAC');

-- COMMAND ----------

SELECT aeroporto_icao, nome_original, nome, municipio, fonte_cadastro
FROM gold.dim_aeroporto
WHERE aeroporto_icao IN ('SBCG', 'SBSR', 'SBIH', 'SBUY', 'SSOU', 'SNCL');

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O histórico do Delta não é histórico de negócio

-- COMMAND ----------

DESCRIBE HISTORY gold.dim_aeroporto;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC O Delta guarda as versões da tabela, e `VERSION AS OF` lê o nome antigo do SBCG. Mas essas versões contam
-- MAGIC quando a tabela mudou, não quando o aeroporto mudou, e somem com o `VACUUM`. Histórico que o negócio consulta
-- MAGIC fica no modelo: é o tipo 2.
-- MAGIC
-- MAGIC ## Resultado da task 10
-- MAGIC
-- MAGIC A dimensão atualizada com o cadastro de 2026, sem perder a chave de nenhum aeroporto, e os aeroportos
-- MAGIC inferidos completados pelo cadastro.
