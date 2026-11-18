-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Escolhendo o SCD com apoio da IA
-- MAGIC
-- MAGIC ## Task 14: decidir o tipo de SCD das mudanças reais dos cadastros, e conferir cada decisão nos dados
-- MAGIC
-- MAGIC A pergunta que decide o tipo: **alguém precisa da resposta como era na data do fato?**

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Os casos
-- MAGIC
-- MAGIC Todos vieram dos cadastros da ANAC. Decida antes de seguir:
-- MAGIC
-- MAGIC | Caso | Mudança | Tipo |
-- MAGIC |---|---|---|
-- MAGIC | SBCG | o nome passou de "CAMPO GRANDE" para "Aeroporto Internacional de Campo Grande - Ueze Elias Zahran" | |
-- MAGIC | SBSR | "Eriberto" passou a "Eribelto" | |
-- MAGIC | SBIH | o município passou de Itaituba para Aveiro | |
-- MAGIC | 11 aeródromos | a altitude mudou de 1 a 11 metros | |
-- MAGIC | 5 aeródromos | a situação alternou entre Cadastrado e Interditado | |
-- MAGIC | GLO | a razão social diz "GOL LINHAS AÉREAS S.A. (EX- VRG LINHAS AÉREAS S.A.)" | |

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## O pedido para a IA
-- MAGIC
-- MAGIC No Databricks Assistant, com a decisão já tomada e o critério do projeto:
-- MAGIC
-- MAGIC > Numa dimensão de aeroportos de um modelo de pontualidade de voos, decidi usar SCD tipo 1 para a mudança de
-- MAGIC > município do aeródromo SBIH, de Itaituba para Aveiro, no cadastro da ANAC. O critério do projeto é: tipo 2 só
-- MAGIC > quando alguém precisa da resposta como era na data do voo. Que informação dos dados eu deveria conferir para
-- MAGIC > saber se essa decisão está certa?
-- MAGIC
-- MAGIC A resposta vai variar. O que importa é transformar cada sugestão numa consulta.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Conferindo: o aeroporto mudou de lugar?

-- COMMAND ----------

SELECT data_cadastro, codigo_oaci, nome, municipio, latitude, longitude, altitude
FROM bronze.aerodromos
WHERE codigo_oaci = 'SBIH'
ORDER BY data_cadastro;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC As coordenadas são as mesmas: o aeródromo não mudou de lugar, o cadastro corrigiu o município. Correção é tipo 1:
-- MAGIC um voo de julho não aconteceu em "outro" município.
-- MAGIC
-- MAGIC ## Conferindo: alguém pergunta pela situação na data do voo?

-- COMMAND ----------

WITH mudaram AS (
  SELECT codigo_oaci
  FROM bronze.aerodromos
  GROUP BY codigo_oaci
  HAVING count(DISTINCT situacao) > 1
)
SELECT m.codigo_oaci, count(v.numero_voo) AS voos_no_recorte
FROM mudaram m
LEFT JOIN silver.voos v ON v.origem_icao = m.codigo_oaci OR v.destino_icao = m.codigo_oaci
GROUP BY ALL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Conferindo: a empresa mudou?

-- COMMAND ----------

SELECT empresa_icao, razao_social FROM gold.dim_empresa WHERE razao_social LIKE '%(EX%';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC A razão social antiga está dentro do texto, num cadastro só: não existe uma segunda entrega para comparar.
-- MAGIC Sem duas versões na fonte, não há o que versionar.
-- MAGIC
-- MAGIC ## Erro que vale procurar na resposta da IA
-- MAGIC
-- MAGIC | Sugestão comum | Por que conferir |
-- MAGIC |---|---|
-- MAGIC | "use tipo 2 em tudo, por segurança" | cada atributo tipo 2 multiplica as versões e obriga o join pelo período em toda consulta |
-- MAGIC | "tipo 3 para o nome" | o painel mostra o nome atual; ninguém pediu o anterior |
-- MAGIC | "use o time travel do Delta como histórico" | as versões contam mudanças na tabela e somem com o `VACUUM` (task 10) |
-- MAGIC
-- MAGIC ## A decisão do projeto
-- MAGIC
-- MAGIC | Atributo | Tipo | Motivo |
-- MAGIC |---|---|---|
-- MAGIC | `ciad`, `nome_original` | 0 | identificam o aeroporto como entrou no modelo |
-- MAGIC | `nome`, `municipio`, coordenadas, `altitude_m`, `situacao` | 1 | correções e renomeações; o painel mostra o atual |
-- MAGIC | `administrador`, `tipo_administracao` | 2 | a pergunta do cliente depende de quem administrava no dia do voo |
-- MAGIC | razão social da empresa | 1 | uma entrega só; reavaliar se o cadastro começar a chegar todo mês |
-- MAGIC
-- MAGIC ## Demanda da aula 3 atendida
-- MAGIC
-- MAGIC | Task | Entrega |
-- MAGIC |---|---|
-- MAGIC | 10 | o cadastro de 2026 aplicado com tipos 0 e 1 |
-- MAGIC | 11 | o administrador versionado com tipo 2 |
-- MAGIC | 12 | a fato ligada à versão da data do voo, com outubro |
-- MAGIC | 13 | a lista de trocas para o painel, e o tipo 3 avaliado |
-- MAGIC | 14 | o tipo de cada atributo, conferido nos dados |
