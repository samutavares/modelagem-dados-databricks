-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Dimensões e chaves
-- MAGIC
-- MAGIC ## Task 6: montar as dimensões de empresa e de aeroporto, com chave própria
-- MAGIC
-- MAGIC | Fonte | Vira |
-- MAGIC |---|---|
-- MAGIC | cadastro de empresas aéreas da ANAC | `gold.dim_empresa` |
-- MAGIC | lista de aeródromos públicos da ANAC (abril de 2025) e aeroportos do exterior | `gold.dim_aeroporto` |

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %python
-- MAGIC import os, shutil
-- MAGIC
-- MAGIC PROJETO = os.path.abspath("../../data")
-- MAGIC VOLUME = "/Volumes/workspace/bronze/arquivos"
-- MAGIC
-- MAGIC for arquivo in ["cadastros/empresas/pda_empresas_aereas_nacionais.csv",
-- MAGIC                 "cadastros/empresas/pda_empresas_aereas_estrangeiros.csv",
-- MAGIC                 "cadastros/aerodromos/AerodromosPublicos_2025-04-15.csv",
-- MAGIC                 "cadastros/aeroportos_exterior/aeroportos_exterior.csv"]:
-- MAGIC     os.makedirs(os.path.dirname(f"{VOLUME}/{arquivo}"), exist_ok=True)
-- MAGIC     shutil.copy(f"{PROJETO}/{arquivo}", f"{VOLUME}/{arquivo}")

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Os cadastros na bronze

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.empresas
COMMENT 'Empresas aéreas nacionais e estrangeiras autorizadas pela ANAC'
AS
SELECT *, _metadata.file_name AS _arquivo
FROM read_files('/Volumes/workspace/bronze/arquivos/cadastros/empresas/',
                format => 'csv', sep => ';', header => true, skipRows => 1, inferColumnTypes => false);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC A lista de aeródromos, lida do mesmo jeito:

-- COMMAND ----------

SELECT *
FROM read_files('/Volumes/workspace/bronze/arquivos/cadastros/aerodromos/AerodromosPublicos_2025-04-15.csv',
                format => 'csv', sep => ';', header => true, skipRows => 1)
LIMIT 5;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC `S�o Paulo`: este arquivo não é UTF-8, é Windows-1252. E o nome `Código OACI` tem acento e espaço, que a
-- MAGIC tabela Delta não aceita sem configuração: a bronze declara os nomes ao ler.

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze.aerodromos
COMMENT 'Lista de aeródromos públicos da ANAC: uma linha por aeródromo e data do cadastro'
AS
SELECT
  `Código OACI` AS codigo_oaci, CIAD AS ciad, Nome AS nome, `Município` AS municipio, UF AS uf,
  LATGEOPOINT AS latitude, LONGEOPOINT AS longitude, Altitude AS altitude, `Situação` AS situacao,
  to_date(regexp_extract(_metadata.file_name, '([0-9]{4}-[0-9]{2}-[0-9]{2})', 1)) AS data_cadastro,
  _metadata.file_name AS _arquivo
FROM read_files('/Volumes/workspace/bronze/arquivos/cadastros/aerodromos/AerodromosPublicos_2025-04-15.csv',
                format => 'csv', sep => ';', header => true, skipRows => 1, encoding => 'windows-1252',
                inferColumnTypes => false);

CREATE OR REPLACE TABLE bronze.aeroportos_exterior
COMMENT 'Aeroportos do exterior que aparecem nos voos, a partir do OurAirports'
AS
SELECT *, _metadata.file_name AS _arquivo
FROM read_files('/Volumes/workspace/bronze/arquivos/cadastros/aeroportos_exterior/',
                format => 'csv', sep => ';', header => true, inferColumnTypes => false);

-- COMMAND ----------

SELECT nome, municipio, uf, altitude FROM bronze.aerodromos WHERE codigo_oaci IN ('SBGR', 'SBGL', 'SBCX');

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Por que uma chave própria (surrogate key)
-- MAGIC
-- MAGIC | Usar o código ICAO como chave | Problema |
-- MAGIC |---|---|
-- MAGIC | um aeroporto com dois registros no tempo (aula 3) | o ICAO se repete |
-- MAGIC | voo com código que nenhum cadastro tem | a fato fica sem par |
-- MAGIC | a fonte troca o padrão do código | a fato inteira muda |
-- MAGIC
-- MAGIC | Jeito de gerar | Vantagem | Custo |
-- MAGIC |---|---|---|
-- MAGIC | coluna `IDENTITY` | número curto e sequencial | muda se a tabela for recriada |
-- MAGIC | hash da chave natural (`xxhash64`) | sempre o mesmo número para o mesmo aeroporto, mesmo recriando | número grande e chance mínima de colisão |
-- MAGIC
-- MAGIC O projeto recria as tabelas a cada carga (aula 4): hash.

-- COMMAND ----------

SELECT codigo_oaci, xxhash64(codigo_oaci) AS chave FROM bronze.aerodromos WHERE codigo_oaci IN ('SBGR', 'SBGL');

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A dimensão de empresa
-- MAGIC
-- MAGIC Três tipos de linha:
-- MAGIC
-- MAGIC - **cadastrada:** veio do cadastro da ANAC;
-- MAGIC - **inferida:** aparece nos voos, mas não no cadastro. Entra com o código e "Não cadastrada", para o voo não
-- MAGIC   sumir do painel;
-- MAGIC - **desconhecida:** a chave `-1`, para quando o voo vier sem empresa.

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.dim_empresa
COMMENT 'Empresas aéreas: uma linha por código ICAO'
AS
WITH cadastradas AS (
  SELECT
    ICAO                                                         AS empresa_icao,
    nullif(nullif(trim(Estrangeira), '..'), '.')                 AS empresa_iata,
    trim(Razao)                                                  AS razao_social,
    CASE WHEN _arquivo LIKE '%estrangeiros%' THEN 'Estrangeira' ELSE 'Brasileira' END AS nacionalidade,
    Servico                                                      AS servico,
    Ativa                                                        AS situacao_cadastro,
    'ANAC'                                                       AS fonte_cadastro
  FROM bronze.empresas
  WHERE nullif(trim(ICAO), '') IS NOT NULL
),
inferidas AS (
  SELECT DISTINCT empresa_icao, NULL, 'Não cadastrada', 'Não informada', NULL, NULL, 'Inferida dos voos'
  FROM silver.voos
  WHERE empresa_icao NOT IN (SELECT empresa_icao FROM cadastradas)
)
SELECT xxhash64(empresa_icao) AS sk_empresa, *
FROM (SELECT * FROM cadastradas UNION ALL SELECT * FROM inferidas)
UNION ALL
SELECT -1, 'N/A', NULL, 'Desconhecida', 'Não informada', NULL, NULL, 'Membro desconhecido';

-- COMMAND ----------

SELECT fonte_cadastro, nacionalidade, count(*) AS empresas FROM gold.dim_empresa GROUP BY ALL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A dimensão de aeroporto
-- MAGIC
-- MAGIC A lista da ANAC traz o estado por extenso. A sigla e a região vêm de uma tabela de referência.

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.ref_uf
COMMENT 'Unidades da federação: nome, sigla e região'
AS
SELECT * FROM VALUES
  ('Acre', 'AC', 'Norte'), ('Alagoas', 'AL', 'Nordeste'), ('Amapá', 'AP', 'Norte'), ('Amazonas', 'AM', 'Norte'),
  ('Bahia', 'BA', 'Nordeste'), ('Ceará', 'CE', 'Nordeste'), ('Distrito Federal', 'DF', 'Centro-Oeste'),
  ('Espírito Santo', 'ES', 'Sudeste'), ('Goiás', 'GO', 'Centro-Oeste'), ('Maranhão', 'MA', 'Nordeste'),
  ('Mato Grosso', 'MT', 'Centro-Oeste'), ('Mato Grosso do Sul', 'MS', 'Centro-Oeste'),
  ('Minas Gerais', 'MG', 'Sudeste'), ('Pará', 'PA', 'Norte'), ('Paraíba', 'PB', 'Nordeste'),
  ('Paraná', 'PR', 'Sul'), ('Pernambuco', 'PE', 'Nordeste'), ('Piauí', 'PI', 'Nordeste'),
  ('Rio de Janeiro', 'RJ', 'Sudeste'), ('Rio Grande do Norte', 'RN', 'Nordeste'),
  ('Rio Grande do Sul', 'RS', 'Sul'), ('Rondônia', 'RO', 'Norte'), ('Roraima', 'RR', 'Norte'),
  ('Santa Catarina', 'SC', 'Sul'), ('São Paulo', 'SP', 'Sudeste'), ('Sergipe', 'SE', 'Nordeste'),
  ('Tocantins', 'TO', 'Norte')
  AS t(uf_nome, uf, regiao);

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.dim_aeroporto
COMMENT 'Aeroportos: uma linha por código ICAO. Usada pela fato como origem e como destino'
AS
WITH brasil AS (
  SELECT
    a.codigo_oaci AS aeroporto_icao, a.ciad, a.nome, a.municipio, u.uf, u.uf_nome, u.regiao,
    'Brasil' AS pais, 'América do Sul' AS continente,
    double(a.latitude) AS latitude, double(a.longitude) AS longitude,
    double(replace(a.altitude, ',', '.')) AS altitude_m, a.situacao, 'ANAC' AS fonte_cadastro
  FROM bronze.aerodromos a
  LEFT JOIN silver.ref_uf u ON a.uf = u.uf_nome
  WHERE a.data_cadastro = DATE'2025-04-15'
),
exterior AS (
  SELECT
    icao, NULL, nome, cidade, NULL, NULL, 'Exterior', pais,
    CASE continente WHEN 'SA' THEN 'América do Sul' WHEN 'NA' THEN 'América do Norte' WHEN 'EU' THEN 'Europa'
                    WHEN 'AF' THEN 'África' WHEN 'AS' THEN 'Ásia' WHEN 'OC' THEN 'Oceania' END,
    double(latitude), double(longitude), NULL, NULL, 'OurAirports'
  FROM bronze.aeroportos_exterior
),
cadastrados AS (SELECT * FROM brasil UNION ALL SELECT * FROM exterior),
inferidos AS (
  SELECT DISTINCT icao, NULL, 'Não cadastrado', NULL, NULL, NULL, 'Não informada', NULL, NULL,
                  NULL, NULL, NULL, NULL, 'Inferido dos voos'
  FROM (SELECT origem_icao AS icao FROM silver.voos UNION SELECT destino_icao FROM silver.voos)
  WHERE icao NOT IN (SELECT aeroporto_icao FROM cadastrados)
)
SELECT xxhash64(aeroporto_icao) AS sk_aeroporto, *
FROM (SELECT * FROM cadastrados UNION ALL SELECT * FROM inferidos)
UNION ALL
SELECT -1, 'N/A', NULL, 'Desconhecido', NULL, NULL, NULL, 'Não informada', NULL, NULL, NULL, NULL, NULL,
       'Membro desconhecido';

-- COMMAND ----------

SELECT fonte_cadastro, count(*) AS aeroportos FROM gold.dim_aeroporto GROUP BY ALL;

-- COMMAND ----------

SELECT aeroporto_icao, nome, fonte_cadastro FROM gold.dim_aeroporto WHERE fonte_cadastro = 'Inferido dos voos';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A chave primária no catálogo
-- MAGIC
-- MAGIC Declarar a chave deixa o modelo legível no Catalog Explorer e para quem consulta. O Unity Catalog guarda a
-- MAGIC restrição como informação.

-- COMMAND ----------

ALTER TABLE gold.dim_data ALTER COLUMN sk_data SET NOT NULL;
ALTER TABLE gold.dim_data ADD CONSTRAINT pk_dim_data PRIMARY KEY (sk_data);

ALTER TABLE gold.dim_empresa ALTER COLUMN sk_empresa SET NOT NULL;
ALTER TABLE gold.dim_empresa ADD CONSTRAINT pk_dim_empresa PRIMARY KEY (sk_empresa);

ALTER TABLE gold.dim_aeroporto ALTER COLUMN sk_aeroporto SET NOT NULL;
ALTER TABLE gold.dim_aeroporto ADD CONSTRAINT pk_dim_aeroporto PRIMARY KEY (sk_aeroporto);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Resultado da task 6
-- MAGIC
-- MAGIC `gold.dim_empresa` e `gold.dim_aeroporto`, com chave própria, membros inferidos e o membro desconhecido.
