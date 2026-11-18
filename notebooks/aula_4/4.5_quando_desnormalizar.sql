-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Quando desnormalizar
-- MAGIC
-- MAGIC ## Task 19: entregar o relatório mensal que vai para os clientes
-- MAGIC
-- MAGIC Todo mês, cada cliente recebe uma planilha com os voos das rotas que os funcionários dele usam. Quem abre a
-- MAGIC planilha não faz join: precisa de uma linha por voo, com os nomes já escritos.

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Estrela, agregada ou tabela larga?
-- MAGIC
-- MAGIC | Consumidor | Faz join? | Melhor entrega |
-- MAGIC |---|---|---|
-- MAGIC | metric view e painel (aula 5) | sim, declarado uma vez | estrela |
-- MAGIC | analista em SQL | sim | estrela |
-- MAGIC | planilha do cliente | não | tabela larga, desnormalizada |
-- MAGIC
-- MAGIC A tabela larga é uma **saída** do modelo, gerada a partir da estrela. Ela não alimenta nenhuma outra tabela: se o
-- MAGIC nome de um aeroporto mudar, muda na dimensão e a tabela larga é recalculada.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC No `gold.py`, a materialized view `gold.relatorio_voos_cliente`. Depois da atualização:

-- COMMAND ----------

SELECT * FROM gold.relatorio_voos_cliente
WHERE origem_municipio = 'RIO DE JANEIRO' AND mes = 'setembro'
LIMIT 20;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Medindo: a mesma pergunta nos dois desenhos
-- MAGIC
-- MAGIC Rode as duas consultas no SQL editor, com o SQL warehouse, e compare o tempo e os bytes lidos no Query Profile.

-- COMMAND ----------

SELECT o.uf, round(100 * try_divide(sum(f.qtd_pontual_partida), sum(f.qtd_realizado)), 2) AS pct_pontual
FROM gold.fato_voo f
JOIN gold.dim_aeroporto o ON o.sk_aeroporto = f.sk_aeroporto_origem
GROUP BY ALL;

-- COMMAND ----------

SELECT origem_uf AS uf, round(100 * avg(CASE WHEN partiu_no_horario = 'sim' THEN 1 ELSE 0 END), 2) AS pct_pontual
FROM gold.relatorio_voos_cliente
WHERE situacao = 'REALIZADO'
GROUP BY ALL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O custo da tabela larga

-- COMMAND ----------

-- MAGIC %python
-- MAGIC for tabela in ["gold.fato_voo", "gold.dim_aeroporto", "gold.relatorio_voos_cliente"]:
-- MAGIC     detalhe = spark.sql(f"DESCRIBE DETAIL {tabela}").first()
-- MAGIC     print(f"{tabela:32} {detalhe['sizeInBytes']:>12,} bytes")

-- COMMAND ----------

-- MAGIC %md
-- MAGIC | Desnormalizar quando | Manter a estrela quando |
-- MAGIC |---|---|
-- MAGIC | o consumidor não faz join (planilha, exportação, sistema externo) | o consumidor faz join ou usa uma camada semântica |
-- MAGIC | o formato da saída é fixo e combinado | as perguntas mudam toda semana |
-- MAGIC | a tabela é recalculada a partir da estrela | seria a fonte de outras tabelas |
-- MAGIC
-- MAGIC ## Resultado da task 19
-- MAGIC
-- MAGIC `gold.relatorio_voos_cliente` como saída do modelo, e o critério de quando desnormalizar.
-- MAGIC
-- MAGIC ## Demanda da aula 4 atendida
-- MAGIC
-- MAGIC | Task | Entrega |
-- MAGIC |---|---|
-- MAGIC | 15 | o pipeline declarativo, da bronze à fato |
-- MAGIC | 16 | a duplicata da republicação, medida e explicada |
-- MAGIC | 17 | a entrega mais recente de cada mês substitui a anterior |
-- MAGIC | 18 | `gold.agg_voo_dia`, conferida contra a fato |
-- MAGIC | 19 | `gold.relatorio_voos_cliente` e o critério de desnormalização |
