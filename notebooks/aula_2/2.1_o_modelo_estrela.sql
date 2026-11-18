-- Databricks notebook source
-- MAGIC %md
-- MAGIC # O modelo estrela
-- MAGIC
-- MAGIC ## Task 5: desenhar o modelo que responde às perguntas do time comercial
-- MAGIC
-- MAGIC | Pergunta | Mede o quê | Por quê |
-- MAGIC |---|---|---|
-- MAGIC | qual empresa atrasa menos no Rio? | atraso, pontualidade | empresa, aeroporto |
-- MAGIC | setembro foi melhor que agosto? | pontualidade | data |
-- MAGIC | quanto cancela à noite na região Sul? | cancelamentos | data, aeroporto |
-- MAGIC
-- MAGIC O que se mede vira **fato**. O "por" vira **dimensão**.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O desenho
-- MAGIC
-- MAGIC ```
-- MAGIC                    dim_data
-- MAGIC                       |
-- MAGIC   dim_empresa ---- fato_voo ---- dim_aeroporto (origem)
-- MAGIC                       |
-- MAGIC                 dim_aeroporto (destino)
-- MAGIC ```
-- MAGIC
-- MAGIC | Peça | Grão |
-- MAGIC |---|---|
-- MAGIC | `fato_voo` | uma etapa de voo programada (aula 1) |
-- MAGIC | `dim_data` | um dia |
-- MAGIC | `dim_empresa` | uma empresa aérea |
-- MAGIC | `dim_aeroporto` | um aeroporto, usado duas vezes pela fato: origem e destino |

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A primeira dimensão: data
-- MAGIC
-- MAGIC Não vem de arquivo nenhum: é gerada. Cada atributo é uma pergunta que o painel pode filtrar sem calcular
-- MAGIC data na hora.

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.dim_data
COMMENT 'Calendário de 2026: uma linha por dia'
AS
WITH dias AS (
  SELECT explode(sequence(DATE'2026-01-01', DATE'2026-12-31', INTERVAL 1 DAY)) AS data
),
feriados AS (
  SELECT * FROM VALUES
    (DATE'2026-01-01', 'Confraternização Universal'), (DATE'2026-04-03', 'Paixão de Cristo'),
    (DATE'2026-04-21', 'Tiradentes'), (DATE'2026-05-01', 'Dia do Trabalho'),
    (DATE'2026-09-07', 'Independência do Brasil'), (DATE'2026-10-12', 'Nossa Senhora Aparecida'),
    (DATE'2026-11-02', 'Finados'), (DATE'2026-11-15', 'Proclamação da República'),
    (DATE'2026-11-20', 'Dia Nacional de Zumbi e da Consciência Negra'), (DATE'2026-12-25', 'Natal')
    AS f(data, feriado)
)
SELECT
  int(date_format(d.data, 'yyyyMMdd'))                       AS sk_data,
  d.data,
  year(d.data)                                               AS ano,
  quarter(d.data)                                            AS trimestre,
  month(d.data)                                              AS mes,
  element_at(array('janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto',
                   'setembro', 'outubro', 'novembro', 'dezembro'), month(d.data)) AS nome_mes,
  date_trunc('MONTH', d.data)::DATE                          AS inicio_mes,
  dayofweek(d.data)                                          AS dia_semana,
  element_at(array('domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'),
             dayofweek(d.data))                              AS nome_dia_semana,
  dayofweek(d.data) IN (1, 7)                                AS fim_de_semana,
  f.feriado IS NOT NULL                                      AS feriado_nacional,
  f.feriado                                                  AS nome_feriado
FROM dias d
LEFT JOIN feriados f USING (data);

-- COMMAND ----------

SELECT * FROM gold.dim_data WHERE mes = 9 AND dia_semana IN (1, 2) OR feriado_nacional ORDER BY data;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Por que a chave da data é um número `aaaammdd`
-- MAGIC
-- MAGIC - a fato guarda um inteiro, não a data inteira de novo;
-- MAGIC - quem lê a fato sem o join ainda entende: `20260907` é 7 de setembro;
-- MAGIC - a mesma chave serve para qualquer fato do projeto que tenha data.
-- MAGIC
-- MAGIC ## Resultado da task 5
-- MAGIC
-- MAGIC O desenho do modelo, com o grão de cada peça, e a `gold.dim_data`.
