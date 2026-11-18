import os
from functools import reduce

from pyspark import pipelines as dp
from pyspark.sql import DataFrame, functions as F

CATALOGO = spark.conf.get("catalogo", "workspace")
VOLUME = f"/Volumes/{CATALOGO}/bronze/arquivos"

ESQUEMA_VRA = """
    icao_empresa STRING, numero_voo STRING, codigo_di STRING, codigo_tipo_linha STRING,
    icao_origem STRING, icao_destino STRING, partida_prevista STRING, partida_real STRING,
    chegada_prevista STRING, chegada_real STRING, situacao_voo STRING, codigo_justificativa STRING
"""


def ler_csv(caminho, encoding="UTF-8", linhas_antes_do_cabecalho=1):
    return (
        spark.read.format("csv")
        .option("sep", ";")
        .option("header", "true")
        .option("skipRows", linhas_antes_do_cabecalho)
        .option("encoding", encoding)
        .load(caminho)
        .withColumn("_arquivo", F.col("_metadata.file_name"))
    )


@dp.table(
    name=f"{CATALOGO}.bronze.voos_vra",
    comment="Voos do VRA da ANAC, linha a linha, como chegaram. Cada arquivo novo do volume entra uma vez.",
)
def voos_vra():
    return (
        spark.readStream.format("cloudFiles")
        .option("cloudFiles.format", "csv")
        .option("sep", ";")
        .option("header", "true")
        .option("skipRows", 1)
        .schema(ESQUEMA_VRA)
        .load(f"{VOLUME}/vra/")
        .select(
            "*",
            F.col("_metadata.file_name").alias("_arquivo"),
            F.col("_metadata.file_modification_time").alias("_recebido_em"),
        )
    )


@dp.table(
    name=f"{CATALOGO}.bronze.administradores",
    comment="Cadastro de administradores de aeroporto: uma linha por aeroporto e início de vigência, por entrega.",
)
def administradores():
    return (
        spark.readStream.format("cloudFiles")
        .option("cloudFiles.format", "csv")
        .option("sep", ";")
        .option("header", "true")
        .schema("icao STRING, administrador STRING, tipo_administracao STRING, vigente_desde STRING, fonte STRING")
        .load(f"{VOLUME}/cadastros/administradores/")
        .select(
            "*",
            F.col("_metadata.file_name").alias("_arquivo"),
            F.col("_metadata.file_modification_time").alias("_recebido_em"),
        )
    )


@dp.materialized_view(
    name=f"{CATALOGO}.bronze.aerodromos",
    comment="Lista de aeródromos públicos da ANAC: uma linha por aeródromo e data do cadastro.",
)
def aerodromos():
    pasta = f"{VOLUME}/cadastros/aerodromos"
    # cada entrega tem colunas diferentes (2025 traz as pistas): lê arquivo a arquivo e escolhe pelo nome
    entregas = [
        ler_csv(f"{pasta}/{nome}", encoding="windows-1252").select(
            F.col("Código OACI").alias("codigo_oaci"),
            F.col("CIAD").alias("ciad"),
            F.col("Nome").alias("nome"),
            F.col("Município").alias("municipio"),
            F.col("UF").alias("uf"),
            F.col("LATGEOPOINT").alias("latitude"),
            F.col("LONGEOPOINT").alias("longitude"),
            F.col("Altitude").alias("altitude"),
            F.col("Situação").alias("situacao"),
            F.to_date(F.regexp_extract("_arquivo", r"(\d{4}-\d{2}-\d{2})", 1)).alias("data_cadastro"),
            "_arquivo",
        )
        for nome in sorted(os.listdir(pasta))
        if nome.endswith(".csv")
    ]
    return reduce(DataFrame.unionByName, entregas)


@dp.materialized_view(
    name=f"{CATALOGO}.bronze.empresas",
    comment="Empresas aéreas nacionais e estrangeiras autorizadas pela ANAC.",
)
def empresas():
    return ler_csv(f"{VOLUME}/cadastros/empresas/")


@dp.materialized_view(
    name=f"{CATALOGO}.bronze.aeroportos_exterior",
    comment="Aeroportos do exterior que aparecem nos voos, a partir do OurAirports.",
)
def aeroportos_exterior():
    return ler_csv(f"{VOLUME}/cadastros/aeroportos_exterior/", linhas_antes_do_cabecalho=0)
