-- Databricks notebook source
-- MAGIC %md
-- MAGIC # SCD tipo 2
-- MAGIC
-- MAGIC ## Task 11: guardar quem administrava cada aeroporto em cada período
-- MAGIC
-- MAGIC Em outubro de 2026, a Aena assumiu o Galeão e a Infraero assumiu Caxias do Sul. Pergunta dos clientes do Rio: a
-- MAGIC pontualidade no Galeão mudou com a troca? Com tipo 1, a resposta é impossível: todo voo do Galeão, de julho a
-- MAGIC outubro, apareceria como Aena.
-- MAGIC
-- MAGIC | Tipo 2 | |
-- MAGIC |---|---|
-- MAGIC | uma mudança | uma linha nova, com chave nova |
-- MAGIC | a linha antiga | continua, com o fim da vigência preenchido |
-- MAGIC | colunas de controle | `inicio_vigencia`, `fim_vigencia`, `versao_atual` |

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %python
-- MAGIC import os, shutil
-- MAGIC
-- MAGIC PROJETO = os.path.abspath("../../data")
-- MAGIC VOLUME = "/Volumes/workspace/bronze/arquivos"
-- MAGIC arquivo = "cadastros/administradores/administradores_2026-09-30.csv"
-- MAGIC os.makedirs(os.path.dirname(f"{VOLUME}/{arquivo}"), exist_ok=True)
-- MAGIC shutil.copy(f"{PROJETO}/{arquivo}", f"{VOLUME}/{arquivo}")

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.administradores
COMMENT 'Cadastro de administradores de aeroporto: uma linha por aeroporto e início de vigência'
AS
SELECT *, _metadata.file_name AS _arquivo
FROM read_files('/Volumes/workspace/bronze/arquivos/cadastros/administradores/administradores_2026-09-30.csv',
                format => 'csv', sep => ';', header => true, inferColumnTypes => false);

SELECT * FROM bronze.administradores WHERE icao IN ('SBGL', 'SBCX', 'SBSP', 'SBRJ');

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A dimensão com versões
-- MAGIC
-- MAGIC A chave deixa de ser só o aeroporto: passa a ser o aeroporto e o início da versão. A fato aponta para a chave
-- MAGIC antiga, então as chaves estrangeiras saem agora e voltam na task 12.

-- COMMAND ----------

ALTER TABLE gold.fato_voo DROP CONSTRAINT IF EXISTS fk_voo_origem;
ALTER TABLE gold.fato_voo DROP CONSTRAINT IF EXISTS fk_voo_destino;

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.dim_aeroporto
COMMENT 'Aeroportos: uma linha por aeroporto e período de administração (SCD tipo 2 no administrador)'
AS
SELECT
  CASE WHEN d.sk_aeroporto = -1 THEN -1
       ELSE xxhash64(d.aeroporto_icao, coalesce(to_date(a.vigente_desde), DATE'1900-01-01')) END AS sk_aeroporto,
  d.* EXCEPT (sk_aeroporto),
  coalesce(a.administrador, CASE WHEN d.pais = 'Brasil' THEN 'Não informado' ELSE 'Não se aplica' END) AS administrador,
  coalesce(a.tipo_administracao, 'Não informado')                     AS tipo_administracao,
  a.fonte                                                             AS fonte_administrador,
  coalesce(to_date(a.vigente_desde), DATE'1900-01-01')                AS inicio_vigencia,
  CAST(NULL AS DATE)                                                  AS fim_vigencia,
  true                                                                AS versao_atual
FROM gold.dim_aeroporto d
LEFT JOIN bronze.administradores a ON a.icao = d.aeroporto_icao;

ALTER TABLE gold.dim_aeroporto ALTER COLUMN sk_aeroporto SET NOT NULL;
ALTER TABLE gold.dim_aeroporto ADD CONSTRAINT pk_dim_aeroporto PRIMARY KEY (sk_aeroporto);

-- COMMAND ----------

SELECT aeroporto_icao, nome, administrador, inicio_vigencia, fim_vigencia, versao_atual
FROM gold.dim_aeroporto
WHERE aeroporto_icao IN ('SBGL', 'SBCX');

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A entrega de outubro

-- COMMAND ----------

-- MAGIC %python
-- MAGIC arquivo = "cadastros/administradores/administradores_2026-10-31.csv"
-- MAGIC shutil.copy(f"{PROJETO}/{arquivo}", f"{VOLUME}/{arquivo}")

-- COMMAND ----------

INSERT INTO bronze.administradores
SELECT *, _metadata.file_name
FROM read_files('/Volumes/workspace/bronze/arquivos/cadastros/administradores/administradores_2026-10-31.csv',
                format => 'csv', sep => ';', header => true, inferColumnTypes => false);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC O que é mudança: linha da entrega nova com administrador diferente da versão atual e início posterior a ela.
-- MAGIC A view leva junto os atributos da versão atual, que a versão nova herda.

-- COMMAND ----------

CREATE OR REPLACE TEMPORARY VIEW mudancas_administrador AS
SELECT
  d.* EXCEPT (sk_aeroporto, administrador, tipo_administracao, fonte_administrador, inicio_vigencia,
              fim_vigencia, versao_atual),
  n.administrador, n.tipo_administracao, n.fonte AS fonte_administrador,
  to_date(n.vigente_desde) AS inicio_vigencia
FROM bronze.administradores n
JOIN gold.dim_aeroporto d ON d.aeroporto_icao = n.icao AND d.versao_atual
WHERE n._arquivo = 'administradores_2026-10-31.csv'
  AND to_date(n.vigente_desde) > d.inicio_vigencia
  AND n.administrador <> d.administrador;

SELECT aeroporto_icao, administrador, inicio_vigencia FROM mudancas_administrador;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Fechar e abrir no mesmo MERGE
-- MAGIC
-- MAGIC Cada mudança entra duas vezes na origem do `MERGE`:
-- MAGIC
-- MAGIC | Cópia | `chave_merge` | Encontra a versão atual? | Ação |
-- MAGIC |---|---|---|---|
-- MAGIC | 1 | o ICAO | sim | fecha a versão atual |
-- MAGIC | 2 | `NULL` | nunca | insere a versão nova |
-- MAGIC
-- MAGIC Um comando só: ou as duas coisas acontecem, ou nenhuma.

-- COMMAND ----------

MERGE INTO gold.dim_aeroporto d
USING (
  SELECT aeroporto_icao AS chave_merge, * FROM mudancas_administrador
  UNION ALL
  SELECT NULL AS chave_merge, * FROM mudancas_administrador
) m
ON d.aeroporto_icao = m.chave_merge AND d.versao_atual
WHEN MATCHED THEN UPDATE SET
  fim_vigencia = m.inicio_vigencia,
  versao_atual = false
WHEN NOT MATCHED AND m.chave_merge IS NULL THEN INSERT
  (sk_aeroporto, aeroporto_icao, ciad, nome, nome_original, municipio, uf, uf_nome, regiao, pais, continente,
   latitude, longitude, altitude_m, situacao, fonte_cadastro, administrador, tipo_administracao,
   fonte_administrador, inicio_vigencia, fim_vigencia, versao_atual)
VALUES
  (xxhash64(m.aeroporto_icao, m.inicio_vigencia), m.aeroporto_icao, m.ciad, m.nome, m.nome_original, m.municipio,
   m.uf, m.uf_nome, m.regiao, m.pais, m.continente, m.latitude, m.longitude, m.altitude_m, m.situacao,
   m.fonte_cadastro, m.administrador, m.tipo_administracao, m.fonte_administrador, m.inicio_vigencia, NULL, true);

-- COMMAND ----------

SELECT sk_aeroporto, aeroporto_icao, administrador, inicio_vigencia, fim_vigencia, versao_atual
FROM gold.dim_aeroporto
WHERE aeroporto_icao IN ('SBGL', 'SBCX')
ORDER BY aeroporto_icao, inicio_vigencia;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC **Rode o MERGE de novo.** Nenhuma linha muda: a view só enxerga mudança em relação à versão atual.
-- MAGIC
-- MAGIC ## Resultado da task 11
-- MAGIC
-- MAGIC A `dim_aeroporto` com uma versão por período de administração, e a entrega de outubro aplicada.
