-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Documentação e linhagem
-- MAGIC
-- MAGIC ## Task 22: qualquer pessoa da empresa entende de onde vem o número do painel, sem perguntar para o time de dados
-- MAGIC
-- MAGIC | Pergunta de quem consome | Onde a resposta fica |
-- MAGIC |---|---|
-- MAGIC | o que é uma linha desta tabela? | o comentário da tabela |
-- MAGIC | o que significa esta coluna? | o comentário da coluna |
-- MAGIC | de onde este número veio? | a linhagem no Catalog Explorer |
-- MAGIC | posso usar esta tabela? | as tags |

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A documentação mora no código
-- MAGIC
-- MAGIC As tabelas do pipeline têm comentário no `comment=` de cada decorator, e a `gold.fato_voo` declara o comentário
-- MAGIC de cada coluna no `schema=`. Se a documentação ficasse só na interface, a próxima atualização do pipeline
-- MAGIC poderia apagá-la; no código, ela é versionada no Git junto com a regra que descreve.

-- COMMAND ----------

DESCRIBE TABLE EXTENDED gold.fato_voo;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O dicionário de dados, do próprio catálogo

-- COMMAND ----------

SELECT t.table_schema AS camada, t.table_name AS tabela, t.comment AS o_que_e_uma_linha
FROM information_schema.tables t
WHERE t.table_schema IN ('bronze', 'silver', 'gold')
ORDER BY camada, tabela;

-- COMMAND ----------

SELECT table_name AS tabela, column_name AS coluna, data_type AS tipo, comment AS significado
FROM information_schema.columns
WHERE table_schema = 'gold' AND table_name = 'fato_voo'
ORDER BY ordinal_position;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Atividade: peça para a IA e diga o que está errado
-- MAGIC
-- MAGIC No Catalog Explorer, abra `gold.agg_voo_dia` e use **AI generate** nos comentários das colunas. Não aceite ainda.
-- MAGIC Para cada comentário, responda com uma consulta:
-- MAGIC
-- MAGIC - `qtd_atraso_medido` é "quantidade de voos atrasados"? Compare com `qtd_realizado`.
-- MAGIC - `qtd_pontual_partida` conta voos no horário sobre os programados ou sobre os realizados?
-- MAGIC - `sk_aeroporto_origem` identifica um aeroporto, ou uma versão dele?
-- MAGIC
-- MAGIC A IA lê o nome da coluna, não a regra. Quem escreve o comentário final é quem conhece a regra; o comentário
-- MAGIC corrigido vai para o `comment=` no `gold.py`.

-- COMMAND ----------

SELECT sum(qtd_atraso_medido) AS qtd_atraso_medido,
       sum(qtd_realizado)     AS qtd_realizado,
       sum(qtd_atraso_30)     AS qtd_atrasados_30
FROM gold.agg_voo_dia;

-- COMMAND ----------

SELECT aeroporto_icao, count(*) AS versoes
FROM gold.dim_aeroporto
GROUP BY aeroporto_icao
HAVING count(*) > 1;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Tags nos schemas
-- MAGIC
-- MAGIC Tag é um par chave e valor, que vira filtro na busca do catálogo.

-- COMMAND ----------

ALTER SCHEMA bronze SET TAGS ('camada' = 'bronze', 'uso' = 'interno da carga');
ALTER SCHEMA silver SET TAGS ('camada' = 'silver', 'uso' = 'time de dados');
ALTER SCHEMA gold   SET TAGS ('camada' = 'gold',   'uso' = 'analytics e painel', 'fonte' = 'ANAC VRA');

COMMENT ON SCHEMA gold IS 'Modelo dimensional de pontualidade: fato_voo no grão de etapa programada, dimensões de data, empresa e aeroporto (SCD tipo 2 no administrador)';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A linhagem
-- MAGIC
-- MAGIC No Catalog Explorer, abra `gold.fato_voo` e a aba **Lineage**:
-- MAGIC
-- MAGIC - para trás: `silver.voos`, as dimensões, a barreira de qualidade, até o volume com os arquivos da ANAC;
-- MAGIC - para frente: a agregada, o relatório dos clientes e, depois das próximas tasks, a metric view e o painel;
-- MAGIC - na coluna `qtd_pontual_partida`, a linhagem de coluna mostra que ela vem de `partida_prevista` e
-- MAGIC   `partida_real` da silver.
-- MAGIC
-- MAGIC A linhagem é registrada pelo Unity Catalog a cada execução: nenhuma linha de código foi escrita para ela.
-- MAGIC
-- MAGIC ## Resultado da task 22
-- MAGIC
-- MAGIC O modelo documentado no código, o dicionário de dados consultável, as tags nos schemas e a linhagem conferida.
