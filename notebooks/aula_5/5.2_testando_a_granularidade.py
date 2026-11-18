# Databricks notebook source
# MAGIC %md
# MAGIC # Testando a granularidade
# MAGIC
# MAGIC ## Task 21: testes do modelo que rodam depois de toda carga, num job agendado
# MAGIC
# MAGIC A barreira da task 20 confere o grão da fato. Outras propriedades do modelo também quebram em silêncio:
# MAGIC
# MAGIC | Teste | O que garante |
# MAGIC |---|---|
# MAGIC | grão da fato | uma linha por etapa programada, e as mesmas linhas da silver |
# MAGIC | grão das dimensões | uma linha por chave |
# MAGIC | integridade referencial | toda chave da fato existe na dimensão |
# MAGIC | membros desconhecidos | a parcela de voos sem empresa ou aeroporto continua pequena |
# MAGIC | vigências do tipo 2 | uma versão atual por aeroporto, sem buraco e sem sobreposição |
# MAGIC | reconciliação | a silver tem exatamente os voos da entrega mais recente de cada mês |

# COMMAND ----------

CATALOGO = "workspace"
spark.sql(f"USE CATALOG {CATALOGO}")

# COMMAND ----------

# MAGIC %md
# MAGIC Cada teste é uma consulta que devolve as **violações**. Zero linhas, o teste passa.

# COMMAND ----------

TESTES = {
    "fato_voo: uma linha por etapa programada": """
        SELECT sk_empresa, numero_voo, partida_prevista FROM gold.fato_voo
        GROUP BY ALL HAVING count(*) > 1
    """,
    "fato_voo: as mesmas linhas da silver": """
        SELECT (SELECT count(*) FROM gold.fato_voo) AS fato, (SELECT count(*) FROM silver.voos) AS silver
        WHERE (SELECT count(*) FROM gold.fato_voo) <> (SELECT count(*) FROM silver.voos)
    """,
    "dim_empresa: uma linha por chave": """
        SELECT sk_empresa FROM gold.dim_empresa GROUP BY sk_empresa HAVING count(*) > 1
    """,
    "dim_aeroporto: uma linha por chave": """
        SELECT sk_aeroporto FROM gold.dim_aeroporto GROUP BY sk_aeroporto HAVING count(*) > 1
    """,
    "fato_voo: toda empresa existe na dimensão": """
        SELECT f.sk_empresa FROM gold.fato_voo f
        LEFT ANTI JOIN gold.dim_empresa e ON e.sk_empresa = f.sk_empresa
    """,
    "fato_voo: todo aeroporto de origem e de destino existe na dimensão": """
        SELECT f.sk_aeroporto_origem FROM gold.fato_voo f
        LEFT ANTI JOIN gold.dim_aeroporto a ON a.sk_aeroporto = f.sk_aeroporto_origem
        UNION ALL
        SELECT f.sk_aeroporto_destino FROM gold.fato_voo f
        LEFT ANTI JOIN gold.dim_aeroporto a ON a.sk_aeroporto = f.sk_aeroporto_destino
    """,
    "fato_voo: toda data existe na dimensão": """
        SELECT f.sk_data FROM gold.fato_voo f
        LEFT ANTI JOIN gold.dim_data d ON d.sk_data = f.sk_data
    """,
    "fato_voo: até 0,5% dos voos com membro desconhecido": """
        SELECT count_if(sk_empresa = -1 OR sk_aeroporto_origem = -1 OR sk_aeroporto_destino = -1) AS desconhecidos,
               count(*) AS voos
        FROM gold.fato_voo
        HAVING desconhecidos > 0.005 * voos
    """,
    "dim_aeroporto: uma versão atual por aeroporto": """
        SELECT aeroporto_icao FROM gold.dim_aeroporto
        GROUP BY aeroporto_icao HAVING count_if(versao_atual) <> 1
    """,
    "dim_aeroporto: cada versão termina onde a próxima começa": """
        SELECT aeroporto_icao, inicio_vigencia, fim_vigencia, proximo_inicio
        FROM (
          SELECT *, lead(inicio_vigencia) OVER (PARTITION BY aeroporto_icao ORDER BY inicio_vigencia) AS proximo_inicio
          FROM gold.dim_aeroporto
        )
        WHERE NOT (fim_vigencia <=> proximo_inicio)
    """,
    "silver.voos: os voos da entrega mais recente de cada mês, uma vez cada": """
        WITH ultima AS (
          SELECT * FROM bronze.voos_vra
          QUALIFY _recebido_em = max(_recebido_em) OVER (PARTITION BY regexp_extract(_arquivo, 'VRA_([0-9]{5,6})', 1))
        )
        SELECT 'esperado' AS lado, count(DISTINCT icao_empresa, numero_voo, left(partida_prevista, 19)) AS voos
        FROM ultima WHERE partida_prevista <> 'null'
        HAVING voos <> (SELECT count(*) FROM silver.voos)
    """,
}

# COMMAND ----------

resultados = []
for nome, consulta in TESTES.items():
    violacoes = spark.sql(consulta).limit(5).collect()
    resultados.append((nome, "passou" if not violacoes else "FALHOU", len(violacoes), str(violacoes[:3])))

display(spark.createDataFrame(resultados, "teste STRING, resultado STRING, violacoes_amostra INT, exemplo STRING"))

# COMMAND ----------

# MAGIC %md
# MAGIC Um teste que falha faz a tarefa do job falhar, e o job avisa por e-mail.

# COMMAND ----------

falhas = [r[0] for r in resultados if r[1] == "FALHOU"]
assert not falhas, f"Testes do modelo falharam: {falhas}"

# COMMAND ----------

# MAGIC %md
# MAGIC ## O job mensal
# MAGIC
# MAGIC 1. **Jobs & Pipelines > Create > Job**, nome `pontualidade_mensal`.
# MAGIC 2. Tarefa `carga`: tipo **Pipeline**, o pipeline `pontualidade`.
# MAGIC 3. Tarefa `testes`: tipo **Notebook**, este notebook, dependendo de `carga`.
# MAGIC 4. **Schedule**: todo dia 29, às 8h. A ANAC publica perto do dia 28.
# MAGIC 5. **Notifications**: e-mail em caso de falha.
# MAGIC
# MAGIC O Free Edition permite até 5 tarefas de job rodando ao mesmo tempo; este job usa 2, uma de cada vez.
# MAGIC
# MAGIC ## Resultado da task 21
# MAGIC
# MAGIC Os testes do modelo num notebook, rodando depois de cada carga no job mensal.
