from pyspark import pipelines as dp

C = spark.conf.get("catalogo", "workspace")


@dp.materialized_view(
    name=f"{C}.gold.verificacao_grao",
    comment="Barreira de qualidade antes da fato: se a silver ou as dimensões tiverem repetição na chave, ou se duas "
            "versões do mesmo aeroporto se sobrepuserem, a atualização falha aqui e a fato não é recalculada.",
)
@dp.expect_or_fail("silver_sem_repeticao_no_grao", "silver_linhas = silver_chaves")
@dp.expect_or_fail("dim_empresa_sem_repeticao_na_chave", "empresa_linhas = empresa_chaves")
@dp.expect_or_fail("dim_aeroporto_sem_repeticao_na_chave", "aeroporto_linhas = aeroporto_chaves")
@dp.expect_or_fail("dim_aeroporto_sem_vigencias_sobrepostas", "vigencias_sobrepostas = 0")
def verificacao_grao():
    return spark.sql(f"""
        SELECT
          (SELECT count(*) FROM {C}.silver.voos) AS silver_linhas,
          (SELECT count(DISTINCT empresa_icao, numero_voo, partida_prevista) FROM {C}.silver.voos) AS silver_chaves,
          (SELECT count(*) FROM {C}.gold.dim_empresa) AS empresa_linhas,
          (SELECT count(DISTINCT sk_empresa) FROM {C}.gold.dim_empresa) AS empresa_chaves,
          (SELECT count(*) FROM {C}.gold.dim_aeroporto) AS aeroporto_linhas,
          (SELECT count(DISTINCT sk_aeroporto) FROM {C}.gold.dim_aeroporto) AS aeroporto_chaves,
          (SELECT count(*)
           FROM {C}.gold.dim_aeroporto a
           JOIN {C}.gold.dim_aeroporto b
             ON a.aeroporto_icao = b.aeroporto_icao
            AND a.sk_aeroporto < b.sk_aeroporto
            AND a.inicio_vigencia < coalesce(b.fim_vigencia, DATE'9999-12-31')
            AND b.inicio_vigencia < coalesce(a.fim_vigencia, DATE'9999-12-31')) AS vigencias_sobrepostas
    """)
