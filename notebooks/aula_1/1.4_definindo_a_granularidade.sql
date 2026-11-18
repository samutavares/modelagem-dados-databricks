-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Definindo a granularidade
-- MAGIC
-- MAGIC ## Task 3: decidir o que é uma linha da tabela de voos, e provar com os dados
-- MAGIC
-- MAGIC O grão é a frase que diz o que uma linha representa. Ele vem antes das colunas: sem ele, ninguém sabe se
-- MAGIC pode somar.
-- MAGIC
-- MAGIC | Candidato | Uma linha é... | Responde pontualidade? |
-- MAGIC |---|---|---|
-- MAGIC | voo por dia | um número de voo num dia | não: um número pode ter várias etapas |
-- MAGIC | etapa de voo programada | uma decolagem planejada de A para B | sim |
-- MAGIC | passageiro | uma pessoa num voo | o VRA não tem esse dado |

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Testando chaves candidatas
-- MAGIC
-- MAGIC Se a chave identifica a linha, o total é igual ao número de chaves distintas.

-- COMMAND ----------

SELECT
  count(*) AS linhas,
  count(DISTINCT icao_empresa, numero_voo, left(partida_prevista, 10)) AS empresa_numero_dia,
  count(DISTINCT icao_empresa, numero_voo, icao_origem, left(partida_prevista, 10)) AS empresa_numero_origem_dia,
  count(DISTINCT icao_empresa, numero_voo, left(partida_prevista, 19)) AS empresa_numero_partida
FROM bronze.voos_vra
WHERE partida_prevista <> 'null';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O que sobra na melhor chave

-- COMMAND ----------

SELECT icao_empresa, numero_voo, left(partida_prevista, 19) AS partida_prevista,
       count(*) AS repeticoes,
       count(DISTINCT codigo_di, situacao_voo, partida_real, chegada_real) AS versoes_diferentes,
       collect_set(_arquivo) AS arquivos
FROM bronze.voos_vra
WHERE partida_prevista <> 'null'
GROUP BY ALL
HAVING count(*) > 1
ORDER BY repeticoes DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC O voo que tem duas versões diferentes:

-- COMMAND ----------

SELECT *
FROM bronze.voos_vra
WHERE icao_empresa = 'AZU' AND numero_voo = '9506' AND partida_prevista LIKE '2026-07-09 04:55%';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O grão do projeto
-- MAGIC
-- MAGIC > Uma linha é uma **etapa de voo programada**: uma empresa, um número de voo e uma partida prevista.
-- MAGIC
-- MAGIC | Caso | Decisão |
-- MAGIC |---|---|
-- MAGIC | linhas idênticas | ficam uma vez |
-- MAGIC | mesma chave, situações diferentes | fica o `REALIZADO`, que é o que aconteceu |
-- MAGIC | sem partida prevista | fora do grão: sem horário planejado, não existe atraso. Vão para uma tabela à parte |
-- MAGIC | o mês do voo | o da partida prevista |

-- COMMAND ----------

SELECT
  count_if(partida_prevista <> 'null') AS no_grao,
  count_if(partida_prevista = 'null') AS fora_do_grao,
  round(100 * try_divide(count_if(partida_prevista = 'null'), count(*)), 1) AS pct_fora
FROM bronze.voos_vra;
