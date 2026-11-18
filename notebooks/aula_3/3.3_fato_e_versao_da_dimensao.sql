-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Fato e versão da dimensão
-- MAGIC
-- MAGIC ## Task 12: ligar cada voo à versão do aeroporto que valia no dia do voo
-- MAGIC
-- MAGIC A dimensão já tem as versões. Falta a fato apontar para a versão certa: o voo de 05/10 no Galeão aponta para a
-- MAGIC RIOgaleão, o de 07/10 aponta para a Aena.

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Os voos de outubro
-- MAGIC
-- MAGIC A ANAC publica cada mês perto do dia 28 do mês seguinte. O arquivo de outubro entra agora no volume e na bronze.

-- COMMAND ----------

-- MAGIC %python
-- MAGIC import os, shutil
-- MAGIC
-- MAGIC PROJETO = os.path.abspath("../../data")
-- MAGIC VOLUME = "/Volumes/workspace/bronze/arquivos"
-- MAGIC shutil.copy(f"{PROJETO}/vra/VRA_202610.csv", f"{VOLUME}/vra/VRA_202610.csv")

-- COMMAND ----------

INSERT INTO bronze.voos_vra
SELECT *, _metadata.file_name, _metadata.file_modification_time
FROM read_files(
  '/Volumes/workspace/bronze/arquivos/vra/VRA_202610.csv',
  format => 'csv', sep => ';', header => true, skipRows => 1,
  schema => 'icao_empresa STRING, numero_voo STRING, codigo_di STRING, codigo_tipo_linha STRING,
             icao_origem STRING, icao_destino STRING, partida_prevista STRING, partida_real STRING,
             chegada_prevista STRING, chegada_real STRING, situacao_voo STRING, codigo_justificativa STRING'
);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC A célula abaixo já vem pronta: é o código da task 4, que refaz a silver com outubro.

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.voos
COMMENT 'Etapas de voo programadas: uma linha por empresa, número de voo e partida prevista'
AS
WITH tipados AS (
  SELECT
    icao_empresa AS empresa_icao, numero_voo, codigo_di, codigo_tipo_linha AS tipo_linha,
    icao_origem AS origem_icao, icao_destino AS destino_icao,
    to_timestamp(left(nullif(partida_prevista, 'null'), 19)) AS partida_prevista,
    to_timestamp(left(nullif(partida_real, 'null'), 19))     AS partida_real,
    to_timestamp(left(nullif(chegada_prevista, 'null'), 19)) AS chegada_prevista,
    to_timestamp(left(nullif(chegada_real, 'null'), 19))     AS chegada_real,
    situacao_voo AS situacao,
    make_date(int(regexp_extract(_arquivo, 'VRA_([0-9]{4})([0-9]{1,2})', 1)),
              int(regexp_extract(_arquivo, 'VRA_([0-9]{4})([0-9]{1,2})', 2)), 1) AS mes_arquivo,
    _arquivo, _recebido_em
  FROM bronze.voos_vra
)
SELECT * EXCEPT (ordem)
FROM (
  SELECT *, row_number() OVER (
              PARTITION BY empresa_icao, numero_voo, partida_prevista
              ORDER BY situacao = 'REALIZADO' DESC,
                       abs(timestampdiff(MINUTE, partida_prevista, partida_real)) ASC NULLS LAST) AS ordem
  FROM tipados
  WHERE partida_prevista IS NOT NULL
)
WHERE ordem = 1;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O join pelo período
-- MAGIC
-- MAGIC A condição deixa de ser só o ICAO: a partida prevista tem que cair dentro da vigência.
-- MAGIC
-- MAGIC `partida_prevista >= inicio_vigencia AND partida_prevista < fim_vigencia`
-- MAGIC
-- MAGIC O início entra e o fim não: no dia da troca, o voo pertence à versão nova, e nunca às duas.

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
  v.numero_voo, v.codigo_di, v.tipo_linha, v.situacao,
  v.partida_prevista, v.partida_real, v.chegada_prevista, v.chegada_real,
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
LEFT JOIN gold.dim_empresa e ON e.empresa_icao = v.empresa_icao
LEFT JOIN gold.dim_aeroporto o
  ON o.aeroporto_icao = v.origem_icao
 AND v.partida_prevista >= o.inicio_vigencia
 AND v.partida_prevista < coalesce(o.fim_vigencia, DATE'9999-12-31')
LEFT JOIN gold.dim_aeroporto d
  ON d.aeroporto_icao = v.destino_icao
 AND v.partida_prevista >= d.inicio_vigencia
 AND v.partida_prevista < coalesce(d.fim_vigencia, DATE'9999-12-31');

ALTER TABLE gold.fato_voo ADD CONSTRAINT fk_voo_data
  FOREIGN KEY (sk_data) REFERENCES gold.dim_data (sk_data);
ALTER TABLE gold.fato_voo ADD CONSTRAINT fk_voo_empresa
  FOREIGN KEY (sk_empresa) REFERENCES gold.dim_empresa (sk_empresa);
ALTER TABLE gold.fato_voo ADD CONSTRAINT fk_voo_origem
  FOREIGN KEY (sk_aeroporto_origem) REFERENCES gold.dim_aeroporto (sk_aeroporto);
ALTER TABLE gold.fato_voo ADD CONSTRAINT fk_voo_destino
  FOREIGN KEY (sk_aeroporto_destino) REFERENCES gold.dim_aeroporto (sk_aeroporto);

-- COMMAND ----------

SELECT count(*) AS linhas_fato, (SELECT count(*) FROM silver.voos) AS linhas_silver FROM gold.fato_voo;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Mesmo número de linhas: com as vigências sem sobreposição, cada voo encontra no máximo uma versão.
-- MAGIC
-- MAGIC ## A pergunta dos clientes do Rio

-- COMMAND ----------

SELECT
  o.administrador,
  min(f.partida_prevista)::DATE                                                     AS de,
  max(f.partida_prevista)::DATE                                                     AS ate,
  sum(f.qtd_programado)                                                             AS voos,
  round(100 * try_divide(sum(f.qtd_pontual_partida), sum(f.qtd_realizado)), 2)      AS pct_pontual_partida,
  round(100 * try_divide(sum(f.qtd_cancelado), sum(f.qtd_programado)), 2)           AS pct_cancelado
FROM gold.fato_voo f
JOIN gold.dim_aeroporto o ON o.sk_aeroporto = f.sk_aeroporto_origem
WHERE o.aeroporto_icao = 'SBGL'
GROUP BY ALL
ORDER BY de;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O erro comum: juntar com a versão atual

-- COMMAND ----------

SELECT
  o.administrador,
  sum(f.qtd_programado) AS voos
FROM silver.voos f
JOIN gold.dim_aeroporto o ON o.aeroporto_icao = f.origem_icao AND o.versao_atual
WHERE o.aeroporto_icao = 'SBGL'
GROUP BY ALL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Com a versão atual, todos os voos desde julho viram Aena. É o mesmo resultado do tipo 1: a dimensão tem o
-- MAGIC histórico, mas a consulta jogou fora.
-- MAGIC
-- MAGIC | Período | O que a comparação mostra | O que ela não mostra |
-- MAGIC |---|---|---|
-- MAGIC | três meses contra alguns dias | a diferença dos números | causa: a pontualidade depende de clima, malha e empresa |
-- MAGIC
-- MAGIC ## Resultado da task 12
-- MAGIC
-- MAGIC A fato com outubro, cada voo ligado à versão do aeroporto que valia na partida prevista.
