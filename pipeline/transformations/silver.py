from pyspark import pipelines as dp
from pyspark.sql import Window, functions as F

CATALOGO = spark.conf.get("catalogo", "workspace")

UFS = [
    ("Acre", "AC", "Norte"), ("Alagoas", "AL", "Nordeste"), ("Amapá", "AP", "Norte"), ("Amazonas", "AM", "Norte"),
    ("Bahia", "BA", "Nordeste"), ("Ceará", "CE", "Nordeste"), ("Distrito Federal", "DF", "Centro-Oeste"),
    ("Espírito Santo", "ES", "Sudeste"), ("Goiás", "GO", "Centro-Oeste"), ("Maranhão", "MA", "Nordeste"),
    ("Mato Grosso", "MT", "Centro-Oeste"), ("Mato Grosso do Sul", "MS", "Centro-Oeste"),
    ("Minas Gerais", "MG", "Sudeste"), ("Pará", "PA", "Norte"), ("Paraíba", "PB", "Nordeste"),
    ("Paraná", "PR", "Sul"), ("Pernambuco", "PE", "Nordeste"), ("Piauí", "PI", "Nordeste"),
    ("Rio de Janeiro", "RJ", "Sudeste"), ("Rio Grande do Norte", "RN", "Nordeste"),
    ("Rio Grande do Sul", "RS", "Sul"), ("Rondônia", "RO", "Norte"), ("Roraima", "RR", "Norte"),
    ("Santa Catarina", "SC", "Sul"), ("São Paulo", "SP", "Sudeste"), ("Sergipe", "SE", "Nordeste"),
    ("Tocantins", "TO", "Norte"),
]


def horario(coluna):
    return F.to_timestamp(F.left(F.nullif(F.col(coluna), F.lit("null")), F.lit(19)))


def voos_tipados():
    mes = F.regexp_extract("_arquivo", r"VRA_(\d{4})(\d{1,2})", 2).cast("int")
    ano = F.regexp_extract("_arquivo", r"VRA_(\d{4})(\d{1,2})", 1).cast("int")
    return spark.read.table(f"{CATALOGO}.bronze.voos_vra").select(
        F.col("icao_empresa").alias("empresa_icao"),
        "numero_voo",
        "codigo_di",
        F.col("codigo_tipo_linha").alias("tipo_linha"),
        F.col("icao_origem").alias("origem_icao"),
        F.col("icao_destino").alias("destino_icao"),
        horario("partida_prevista").alias("partida_prevista"),
        horario("partida_real").alias("partida_real"),
        horario("chegada_prevista").alias("chegada_prevista"),
        horario("chegada_real").alias("chegada_real"),
        F.col("situacao_voo").alias("situacao"),
        F.make_date(ano, mes, F.lit(1)).alias("mes_arquivo"),
        "_arquivo",
        "_recebido_em",
    )


def ultima_entrega_de_cada_mes(voos):
    # a ANAC republica o mês inteiro: vale só o arquivo mais recente de cada mês
    mais_recente = F.max("_recebido_em").over(Window.partitionBy("mes_arquivo"))
    return voos.withColumn("_mais_recente", mais_recente).filter("_recebido_em = _mais_recente").drop("_mais_recente")


GRAO = ["empresa_icao", "numero_voo", "partida_prevista"]


@dp.materialized_view(name=f"{CATALOGO}.silver.ref_uf", comment="Unidades da federação: nome, sigla e região.")
def ref_uf():
    return spark.createDataFrame(UFS, "uf_nome STRING, uf STRING, regiao STRING")


@dp.materialized_view(
    name=f"{CATALOGO}.silver.voos",
    comment="Etapas de voo programadas: uma linha por empresa, número de voo e partida prevista. "
            "De cada mês, vale a entrega mais recente da ANAC.",
)
@dp.expect("situacao_conhecida", "situacao IN ('REALIZADO', 'CANCELADO')")
@dp.expect("realizado_tem_partida_real", "situacao <> 'REALIZADO' OR partida_real IS NOT NULL")
@dp.expect("adiantamento_ate_60_min", "partida_real IS NULL OR partida_real >= partida_prevista - INTERVAL 60 MINUTES")
def voos():
    ordem = Window.partitionBy(*GRAO).orderBy(
        F.when(F.col("situacao") == "REALIZADO", 0).otherwise(1),
        F.abs(F.expr("timestampdiff(MINUTE, partida_prevista, partida_real)")).asc_nulls_last(),
    )
    return (
        ultima_entrega_de_cada_mes(voos_tipados())
        .filter("partida_prevista IS NOT NULL")
        .withColumn("_ordem", F.row_number().over(ordem))
        .filter("_ordem = 1")
        .drop("_ordem")
    )


@dp.materialized_view(
    name=f"{CATALOGO}.silver.voos_conflitos",
    comment="Chaves do grão com mais de uma versão na mesma entrega: o que a regra de desempate escolheu e o que descartou.",
)
def voos_conflitos():
    voos = ultima_entrega_de_cada_mes(voos_tipados()).filter("partida_prevista IS NOT NULL")
    versoes = F.size(F.collect_set(F.struct("codigo_di", "situacao", "partida_real", "chegada_real")).over(
        Window.partitionBy(*GRAO)))
    return voos.withColumn("versoes", versoes).filter("versoes > 1")


@dp.materialized_view(
    name=f"{CATALOGO}.silver.voos_sem_partida_prevista",
    comment="Voos sem partida prevista: fora do grão de etapa programada.",
)
def voos_sem_partida_prevista():
    return ultima_entrega_de_cada_mes(voos_tipados()).filter("partida_prevista IS NULL")


@dp.temporary_view(name="administradores_tipados")
def administradores_tipados():
    return (
        spark.readStream.table(f"{CATALOGO}.bronze.administradores")
        .withColumn("vigente_desde", F.to_date("vigente_desde"))
    )


dp.create_streaming_table(
    name=f"{CATALOGO}.silver.administradores_historico",
    comment="Administrador de cada aeroporto por período (SCD tipo 2), com a vigência informada no cadastro.",
)

# o mesmo aeroporto e a mesma data se repetem nas entregas: _recebido_em desempata
dp.create_auto_cdc_flow(
    target=f"{CATALOGO}.silver.administradores_historico",
    source="administradores_tipados",
    keys=["icao"],
    sequence_by=F.struct("vigente_desde", "_recebido_em"),
    stored_as_scd_type=2,
    track_history_column_list=["administrador", "tipo_administracao"],
    except_column_list=["_arquivo", "_recebido_em"],
)
