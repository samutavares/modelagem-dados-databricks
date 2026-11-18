-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Reprocessando o mês corrigido
-- MAGIC
-- MAGIC ## Task 17: fazer a entrega nova de um mês substituir a antiga, sem duplicar e sem apagar os outros meses
-- MAGIC
-- MAGIC | Opção | O que faz com agosto | Problema |
-- MAGIC |---|---|---|
-- MAGIC | apagar o arquivo antigo e reprocessar tudo | some com o agosto antigo | a bronze perde o que chegou; o próximo erro não tem como ser investigado |
-- MAGIC | desempatar pela regra da task 4 | escolhe uma linha por voo | escolhe pela situação, não pela entrega: pode ficar com o valor antigo |
-- MAGIC | AUTO CDC com a chave do voo | atualiza voo a voo | um voo que a ANAC tirou do mês continua na silver |
-- MAGIC | **a entrega mais recente de cada mês vale inteira** | troca o mês | |
-- MAGIC
-- MAGIC A unidade de substituição é a mesma unidade em que a ANAC publica: o mês.

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A mudança no pipeline
-- MAGIC
-- MAGIC No `silver.py`, a `silver.voos` deixa de ser streaming table e vira materialized view, com dois passos:
-- MAGIC
-- MAGIC ```python
-- MAGIC def ultima_entrega_de_cada_mes(voos):
-- MAGIC     mais_recente = F.max("_recebido_em").over(Window.partitionBy("mes_arquivo"))
-- MAGIC     return voos.withColumn("_mais_recente", mais_recente).filter("_recebido_em = _mais_recente").drop("_mais_recente")
-- MAGIC
-- MAGIC @dp.materialized_view(name=f"{CATALOGO}.silver.voos", ...)
-- MAGIC def voos():
-- MAGIC     ordem = Window.partitionBy(*GRAO).orderBy(...)   # a regra de desempate da task 4, de volta
-- MAGIC     return (
-- MAGIC         ultima_entrega_de_cada_mes(voos_tipados())
-- MAGIC         .filter("partida_prevista IS NOT NULL")
-- MAGIC         .withColumn("_ordem", F.row_number().over(ordem))
-- MAGIC         .filter("_ordem = 1")
-- MAGIC         .drop("_ordem")
-- MAGIC     )
-- MAGIC ```
-- MAGIC
-- MAGIC A bronze continua streaming table: guarda as duas entregas de agosto, como chegaram.
-- MAGIC
-- MAGIC Trocar o tipo da tabela exige recriá-la: rode a atualização com **Full refresh** na `silver.voos`.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Conferindo

-- COMMAND ----------

SELECT _arquivo, count(*) AS linhas_na_bronze FROM bronze.voos_vra GROUP BY ALL ORDER BY _arquivo;

-- COMMAND ----------

SELECT _arquivo, mes_arquivo, count(*) AS linhas_na_silver FROM silver.voos GROUP BY ALL ORDER BY mes_arquivo;

-- COMMAND ----------

SELECT count(*) - count(DISTINCT empresa_icao, numero_voo, partida_prevista) AS repetidos_no_grao
FROM silver.voos;

-- COMMAND ----------

SELECT d.nome_mes,
       sum(f.qtd_programado)                                                         AS voos,
       round(100 * try_divide(sum(f.qtd_pontual_partida), sum(f.qtd_realizado)), 2)  AS pct_pontual_partida
FROM gold.fato_voo f
JOIN gold.dim_data d ON d.sk_data = f.sk_data
GROUP BY d.mes, d.nome_mes
ORDER BY d.mes;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Agosto com os voos de 30 e 31, que faltavam na primeira entrega, e sem nenhuma linha repetida.
-- MAGIC
-- MAGIC **Rode o pipeline de novo, sem mudar nada.** Os números não mudam: a carga é idempotente.
-- MAGIC
-- MAGIC ## O que essa decisão não resolve
-- MAGIC
-- MAGIC - se a ANAC mandar um arquivo com parte do mês, ele substitui o mês inteiro;
-- MAGIC - a ordem vem do horário em que o arquivo chegou ao volume: um arquivo antigo enviado depois de um novo vence.
-- MAGIC
-- MAGIC ## Resultado da task 17
-- MAGIC
-- MAGIC A entrega mais recente de cada mês substitui a anterior, a bronze guarda as duas, e a carga pode rodar quantas
-- MAGIC vezes for preciso.
