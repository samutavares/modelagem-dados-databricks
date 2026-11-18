from pyspark import pipelines as dp

C = spark.conf.get("catalogo", "workspace")


@dp.materialized_view(name=f"{C}.gold.dim_data", comment="Calendário de 2026: uma linha por dia.")
def dim_data():
    return spark.sql("""
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
          int(date_format(d.data, 'yyyyMMdd')) AS sk_data,
          d.data,
          year(d.data) AS ano,
          quarter(d.data) AS trimestre,
          month(d.data) AS mes,
          element_at(array('janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto',
                           'setembro', 'outubro', 'novembro', 'dezembro'), month(d.data)) AS nome_mes,
          date_trunc('MONTH', d.data)::DATE AS inicio_mes,
          dayofweek(d.data) AS dia_semana,
          element_at(array('domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'),
                     dayofweek(d.data)) AS nome_dia_semana,
          dayofweek(d.data) IN (1, 7) AS fim_de_semana,
          f.feriado IS NOT NULL AS feriado_nacional,
          f.feriado AS nome_feriado
        FROM dias d
        LEFT JOIN feriados f USING (data)
    """)


@dp.materialized_view(name=f"{C}.gold.dim_empresa", comment="Empresas aéreas: uma linha por código ICAO.")
def dim_empresa():
    return spark.sql(f"""
        WITH cadastradas AS (
          SELECT
            ICAO AS empresa_icao,
            nullif(nullif(trim(Estrangeira), '..'), '.') AS empresa_iata,
            trim(Razao) AS razao_social,
            CASE WHEN _arquivo LIKE '%estrangeiros%' THEN 'Estrangeira' ELSE 'Brasileira' END AS nacionalidade,
            Servico AS servico,
            Ativa AS situacao_cadastro,
            'ANAC' AS fonte_cadastro
          FROM {C}.bronze.empresas
          WHERE nullif(trim(ICAO), '') IS NOT NULL
        ),
        inferidas AS (
          SELECT DISTINCT empresa_icao, NULL, 'Não cadastrada', 'Não informada', NULL, NULL, 'Inferida dos voos'
          FROM {C}.silver.voos
          WHERE empresa_icao NOT IN (SELECT empresa_icao FROM cadastradas)
        )
        SELECT xxhash64(empresa_icao) AS sk_empresa, *
        FROM (SELECT * FROM cadastradas UNION ALL SELECT * FROM inferidas)
        UNION ALL
        SELECT -1, 'N/A', NULL, 'Desconhecida', 'Não informada', NULL, NULL, 'Membro desconhecido'
    """)


@dp.materialized_view(
    name=f"{C}.gold.dim_aeroporto",
    comment="Aeroportos: uma linha por aeroporto e período de administração. "
            "Tipo 0: ciad e nome_original. Tipo 1: nome, município, coordenadas, altitude e situação. "
            "Tipo 2: administrador e tipo_administracao.",
)
def dim_aeroporto():
    return spark.sql(f"""
        WITH cadastro AS (
          SELECT *,
                 row_number() OVER (PARTITION BY codigo_oaci ORDER BY data_cadastro DESC) AS ordem_recente,
                 first_value(nome) OVER (PARTITION BY codigo_oaci ORDER BY data_cadastro) AS primeiro_nome,
                 first_value(ciad) OVER (PARTITION BY codigo_oaci ORDER BY data_cadastro) AS primeiro_ciad
          FROM {C}.bronze.aerodromos
        ),
        brasil AS (
          SELECT
            c.codigo_oaci AS aeroporto_icao, c.primeiro_ciad AS ciad, c.nome, c.primeiro_nome AS nome_original,
            c.municipio, u.uf, u.uf_nome, u.regiao, 'Brasil' AS pais, 'América do Sul' AS continente,
            double(c.latitude) AS latitude, double(c.longitude) AS longitude,
            double(replace(c.altitude, ',', '.')) AS altitude_m, c.situacao, 'ANAC' AS fonte_cadastro
          FROM cadastro c
          LEFT JOIN {C}.silver.ref_uf u ON c.uf = u.uf_nome
          WHERE c.ordem_recente = 1
        ),
        exterior AS (
          SELECT
            icao, NULL, nome, nome, cidade, NULL, NULL, 'Exterior', pais,
            CASE continente WHEN 'SA' THEN 'América do Sul' WHEN 'NA' THEN 'América do Norte'
                            WHEN 'EU' THEN 'Europa' WHEN 'AF' THEN 'África' WHEN 'AS' THEN 'Ásia'
                            WHEN 'OC' THEN 'Oceania' END,
            double(latitude), double(longitude), NULL, NULL, 'OurAirports'
          FROM {C}.bronze.aeroportos_exterior
        ),
        cadastrados AS (SELECT * FROM brasil UNION ALL SELECT * FROM exterior),
        inferidos AS (
          SELECT DISTINCT icao, NULL, 'Não cadastrado', NULL, NULL, NULL, NULL, 'Não informada', NULL, NULL,
                          NULL, NULL, NULL, NULL, 'Inferido dos voos'
          FROM (SELECT origem_icao AS icao FROM {C}.silver.voos
                UNION SELECT destino_icao FROM {C}.silver.voos)
          WHERE icao NOT IN (SELECT aeroporto_icao FROM cadastrados)
        ),
        aeroportos AS (SELECT * FROM cadastrados UNION ALL SELECT * FROM inferidos),
        historico AS (
          SELECT icao, administrador, tipo_administracao, fonte AS fonte_administrador,
                 __START_AT.vigente_desde AS inicio_vigencia,
                 __END_AT.vigente_desde AS fim_vigencia
          FROM {C}.silver.administradores_historico
        )
        SELECT
          xxhash64(a.aeroporto_icao, coalesce(h.inicio_vigencia, DATE'1900-01-01')) AS sk_aeroporto,
          a.*,
          coalesce(h.administrador,
                   CASE WHEN a.pais = 'Brasil' THEN 'Não informado' ELSE 'Não se aplica' END) AS administrador,
          coalesce(h.tipo_administracao, 'Não informado') AS tipo_administracao,
          h.fonte_administrador,
          coalesce(h.inicio_vigencia, DATE'1900-01-01') AS inicio_vigencia,
          h.fim_vigencia,
          h.fim_vigencia IS NULL AS versao_atual
        FROM aeroportos a
        LEFT JOIN historico h ON h.icao = a.aeroporto_icao
        UNION ALL
        SELECT -1, 'N/A', NULL, 'Desconhecido', NULL, NULL, NULL, NULL, 'Não informada', NULL, NULL, NULL, NULL,
               NULL, NULL, 'Membro desconhecido', 'Não informado', 'Não informado', NULL, DATE'1900-01-01', NULL, true
    """)


@dp.materialized_view(
    name=f"{C}.gold.fato_voo",
    comment="Voos: uma linha por etapa de voo programada (empresa, número do voo e partida prevista). "
            "Os aeroportos apontam para a versão que valia na partida prevista.",
    schema="""
        sk_data INT COMMENT 'Dia da partida prevista, aaaammdd. Liga com dim_data',
        sk_empresa BIGINT COMMENT 'Empresa aérea. -1 quando desconhecida',
        sk_aeroporto_origem BIGINT COMMENT 'Versão do aeroporto de origem na data da partida prevista',
        sk_aeroporto_destino BIGINT COMMENT 'Versão do aeroporto de destino na data da partida prevista',
        numero_voo STRING COMMENT 'Número do voo, como a ANAC publica. Pode ter letra',
        codigo_di STRING COMMENT 'Tipo de autorização do voo na ANAC. 0 é o voo regular planejado',
        tipo_linha STRING COMMENT 'N nacional, I internacional, G e C outras naturezas de operação',
        situacao STRING COMMENT 'REALIZADO ou CANCELADO',
        partida_prevista TIMESTAMP COMMENT 'Horário planejado de partida. Parte do grão',
        partida_real TIMESTAMP COMMENT 'Horário em que a partida aconteceu. Nulo nos cancelados',
        chegada_prevista TIMESTAMP COMMENT 'Horário planejado de chegada',
        chegada_real TIMESTAMP COMMENT 'Horário em que a chegada aconteceu. Nulo nos cancelados',
        qtd_programado INT COMMENT 'Sempre 1. Soma: voos programados',
        qtd_realizado INT COMMENT '1 se realizado. Soma: voos realizados',
        qtd_cancelado INT COMMENT '1 se cancelado. Soma: voos cancelados',
        atraso_partida_min INT COMMENT 'Minutos entre a partida prevista e a real. Negativo quando adiantado',
        atraso_chegada_min INT COMMENT 'Minutos entre a chegada prevista e a real. Negativo quando adiantado',
        qtd_pontual_partida INT COMMENT '1 se partiu até 15 minutos depois do previsto',
        qtd_pontual_chegada INT COMMENT '1 se chegou até 15 minutos depois do previsto',
        qtd_atraso_30 INT COMMENT '1 se partiu mais de 30 minutos depois do previsto',
        qtd_atraso_60 INT COMMENT '1 se partiu mais de 60 minutos depois do previsto'
    """,
)
def fato_voo():
    return spark.sql(f"""
        WITH voos AS (
          SELECT *,
                 int(timestampdiff(MINUTE, partida_prevista, partida_real)) AS atraso_partida_min,
                 int(timestampdiff(MINUTE, chegada_prevista, chegada_real)) AS atraso_chegada_min
          FROM {C}.silver.voos
        )
        SELECT
          int(date_format(v.partida_prevista, 'yyyyMMdd')) AS sk_data,
          coalesce(e.sk_empresa, -1) AS sk_empresa,
          coalesce(o.sk_aeroporto, -1) AS sk_aeroporto_origem,
          coalesce(d.sk_aeroporto, -1) AS sk_aeroporto_destino,
          v.numero_voo, v.codigo_di, v.tipo_linha, v.situacao,
          v.partida_prevista, v.partida_real, v.chegada_prevista, v.chegada_real,
          1 AS qtd_programado,
          int(v.situacao = 'REALIZADO') AS qtd_realizado,
          int(v.situacao = 'CANCELADO') AS qtd_cancelado,
          v.atraso_partida_min,
          v.atraso_chegada_min,
          int(coalesce(v.atraso_partida_min <= 15, false)) AS qtd_pontual_partida,
          int(coalesce(v.atraso_chegada_min <= 15, false)) AS qtd_pontual_chegada,
          int(coalesce(v.atraso_partida_min > 30, false)) AS qtd_atraso_30,
          int(coalesce(v.atraso_partida_min > 60, false)) AS qtd_atraso_60
        FROM voos v
        -- a fato depende da barreira de qualidade: se ela falhar, a fato não é recalculada
        CROSS JOIN (SELECT 1 FROM {C}.gold.verificacao_grao LIMIT 1) AS barreira
        LEFT JOIN {C}.gold.dim_empresa e ON e.empresa_icao = v.empresa_icao
        LEFT JOIN {C}.gold.dim_aeroporto o
          ON o.aeroporto_icao = v.origem_icao
         AND v.partida_prevista >= o.inicio_vigencia
         AND v.partida_prevista < coalesce(o.fim_vigencia, DATE'9999-12-31')
        LEFT JOIN {C}.gold.dim_aeroporto d
          ON d.aeroporto_icao = v.destino_icao
         AND v.partida_prevista >= d.inicio_vigencia
         AND v.partida_prevista < coalesce(d.fim_vigencia, DATE'9999-12-31')
    """)


@dp.materialized_view(
    name=f"{C}.gold.agg_voo_dia",
    comment="Voos agregados: uma linha por dia, empresa, aeroporto de origem (versão) e tipo de linha. "
            "Só medidas aditivas; o atraso médio é soma_atraso_partida_min / qtd_atraso_medido.",
)
def agg_voo_dia():
    return spark.sql(f"""
        SELECT
          sk_data, sk_empresa, sk_aeroporto_origem, tipo_linha,
          sum(qtd_programado)       AS qtd_programado,
          sum(qtd_realizado)        AS qtd_realizado,
          sum(qtd_cancelado)        AS qtd_cancelado,
          sum(qtd_pontual_partida)  AS qtd_pontual_partida,
          sum(qtd_pontual_chegada)  AS qtd_pontual_chegada,
          sum(qtd_atraso_30)        AS qtd_atraso_30,
          sum(qtd_atraso_60)        AS qtd_atraso_60,
          sum(atraso_partida_min)   AS soma_atraso_partida_min,
          count(atraso_partida_min) AS qtd_atraso_medido
        FROM {C}.gold.fato_voo
        GROUP BY ALL
    """)


@dp.materialized_view(
    name=f"{C}.gold.relatorio_voos_cliente",
    comment="Tabela desnormalizada para o relatório mensal enviado aos clientes: uma linha por voo, "
            "com os atributos das dimensões já resolvidos. Derivada do modelo estrela; não é fonte para outras tabelas.",
)
def relatorio_voos_cliente():
    return spark.sql(f"""
        SELECT
          dt.data                         AS data_partida_prevista,
          dt.nome_mes                     AS mes,
          e.empresa_iata,
          e.razao_social                  AS empresa,
          f.numero_voo,
          o.aeroporto_icao                AS origem_icao,
          o.nome                          AS origem_nome,
          o.municipio                     AS origem_municipio,
          o.uf                            AS origem_uf,
          o.administrador                 AS origem_administrador,
          d.aeroporto_icao                AS destino_icao,
          d.nome                          AS destino_nome,
          d.municipio                     AS destino_municipio,
          d.uf                            AS destino_uf,
          f.partida_prevista,
          f.partida_real,
          f.situacao,
          f.atraso_partida_min,
          CASE WHEN f.qtd_pontual_partida = 1 THEN 'sim' ELSE 'não' END AS partiu_no_horario
        FROM {C}.gold.fato_voo f
        JOIN {C}.gold.dim_data dt     ON dt.sk_data = f.sk_data
        JOIN {C}.gold.dim_empresa e   ON e.sk_empresa = f.sk_empresa
        JOIN {C}.gold.dim_aeroporto o ON o.sk_aeroporto = f.sk_aeroporto_origem
        JOIN {C}.gold.dim_aeroporto d ON d.sk_aeroporto = f.sk_aeroporto_destino
    """)
