"""Monta a pasta data/ do curso a partir das fontes públicas.

Uso, na raiz do projeto:  python scripts/preparar_dados.py

Baixa os arquivos da ANAC e do OurAirports e gera os arquivos derivados descritos em data/README.md:
a primeira entrega de agosto (simulada), o cadastro de administradores e os aeroportos do exterior.
Os arquivos já baixados não são baixados de novo; apague o arquivo para forçar o download.
"""
import csv
import io
import re
import sys
import urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
DATA = RAIZ / "data"
ANAC = "https://sistemas.anac.gov.br/dadosabertos"
VRA = ANAC + "/Voos%20e%20opera%C3%A7%C3%B5es%20a%C3%A9reas/Voo%20Regular%20Ativo%20(VRA)/2026"
MESES = {7: "07%20-%20Julho", 8: "08%20-%20Agosto", 9: "09%20-%20Setembro", 10: "10%20-%20Outubro"}

FONTES = {
    "cadastros/aerodromos/AerodromosPublicos_2026-11-15.csv":
        ANAC + "/Aerodromos/Aer%C3%B3dromos%20P%C3%BAblicos/Lista%20de%20aer%C3%B3dromos%20p%C3%BAblicos/AerodromosPublicos.csv",
    "cadastros/aerodromos/AerodromosPublicos_2025-04-15.csv":
        "https://web.archive.org/web/20250418153253id_/" + ANAC
        + "/Aerodromos/Aer%C3%B3dromos%20P%C3%BAblicos/Lista%20de%20aer%C3%B3dromos%20p%C3%BAblicos/AerodromosPublicos.csv",
    "cadastros/empresas/pda_empresas_aereas_nacionais.csv":
        ANAC + "/Operador%20A%C3%A9reo/Empresas%20Aereas%20Nacionais/pda_empresas_aereas_nacionais.csv",
    "cadastros/empresas/pda_empresas_aereas_estrangeiros.csv":
        ANAC + "/Operador%20A%C3%A9reo/Empresas%20Aereas%20Estrangeiras/pda_empresas_aereas_estrangeiros.csv",
    "cadastros/concessoes/Concessoes_Aeroportos.csv":
        ANAC + "/Certifica%C3%A7%C3%A3o%20e%20Outorga/Dados%20Gerais%20das%20Concessoes%20de%20Aeroportos/Concessoes_Aeroportos.csv",
}
PREFIXOS_BRASIL = {"SB", "SD", "SI", "SJ", "SN", "SS", "SW"}
OURAIRPORTS = "https://raw.githubusercontent.com/davidmegginson/ourairports-data/main"

# Mudanças de administrador de outubro de 2026, com fonte pública
MUDANCAS_OUTUBRO = [
    ("SBGL", "Aena (Concessionária Aeroporto Rio de Janeiro S.A.)", "Concessão federal", "2026-10-06",
     "https://www.gov.br/anac/pt-br/noticias/2026/concluida-a-venda-assistida-do-aeroporto-do-galeao"),
    ("SBCX", "Infraero", "Pública", "2026-10-09",
     "https://caxias.rs.gov.br/noticias/2026/10/infraero-assume-operacao-do-aeroporto-hugo-cantergiani-nesta-sexta-feira"),
]
ANTES_OUTUBRO = {
    "SBGL": ("RIOgaleão (Concessionária Aeroporto Rio de Janeiro S.A.)", "Concessão federal"),
    "SBCX": ("Prefeitura de Caxias do Sul", "Pública"),
}


def baixar(url, destino):
    if destino.exists():
        return True
    destino.parent.mkdir(parents=True, exist_ok=True)
    try:
        with urllib.request.urlopen(url, timeout=300) as r:
            conteudo = r.read()
    except Exception as erro:
        print(f"  não baixou {destino.name}: {erro}")
        return False
    if len(conteudo) < 200:
        print(f"  {destino.name} ainda não publicado")
        return False
    destino.write_bytes(conteudo)
    print(f"  {destino.relative_to(RAIZ)}  {len(conteudo):,} bytes")
    return True


def baixar_vra():
    print("VRA")
    for mes, pasta in MESES.items():
        baixar(f"{VRA}/{pasta}/VRA_2026{mes}.csv", DATA / "vra" / f"VRA_2026{mes}.csv")
    # a versão republicada de agosto é a que a ANAC publica hoje
    origem = DATA / "vra" / "VRA_20268.csv"
    destino = DATA / "vra_republicado" / "VRA_20268_republicado.csv"
    if origem.exists() and not destino.exists():
        destino.parent.mkdir(parents=True, exist_ok=True)
        destino.write_bytes(origem.read_bytes())
        gerar_primeira_entrega_agosto(origem)


def gerar_primeira_entrega_agosto(arquivo):
    """Simula a primeira entrega de agosto: sem os voos de 30 e 31/08, com a data de 28/09."""
    linhas = arquivo.read_text(encoding="utf-8-sig").splitlines(keepends=True)
    saida = ["Atualizado em: 2026-09-28\n", linhas[1]]
    removidas = 0
    for linha in linhas[2:]:
        partes = linha.split(";")
        partida = partes[6].strip('"') if len(partes) > 6 else ""
        referencia = partida if partida != "null" else partes[7].strip('"')
        if referencia[:10] in ("2026-08-30", "2026-08-31"):
            removidas += 1
            continue
        saida.append(linha)
    arquivo.write_text("\ufeff" + "".join(saida), encoding="utf-8")
    print(f"  primeira entrega de agosto: {len(saida) - 2:,} voos ({removidas:,} retirados)")


def baixar_cadastros():
    print("Cadastros")
    for relativo, url in FONTES.items():
        baixar(url, DATA / relativo)


def concessoes():
    texto = (DATA / "cadastros/concessoes/Concessoes_Aeroportos.csv").read_text(encoding="utf-8-sig")
    leitor = csv.DictReader(io.StringIO(texto.split("\n", 1)[1]), delimiter=";")
    por_aeroporto = {}
    for linha in leitor:
        # no OBJETO os códigos vêm colados à UF anterior ("Aracajú/SESBKG"), por isso sem fronteira de palavra
        codigos = set(re.findall(r"SB[A-Z]{2}", linha["CONTRATO_CONCESSAO"] + " " + linha["OBJETO"]))
        # o CSV traz "SBRJ - Jacarepaguá"; SBRJ é Santos Dumont e Jacarepaguá é SBJR (página de concessões da ANAC)
        if "Jacarepagu" in linha["OBJETO"] and "SBRJ" in codigos:
            codigos = (codigos - {"SBRJ"}) | {"SBJR"}
        for codigo in codigos:
            por_aeroporto[codigo] = (" ".join(linha["NOME_CONCESSIONARIA"].split()).rstrip(" -"),
                                     linha["DATA_EFICACIA"][:10], linha["CONTRATO_CONCESSAO"])
    return por_aeroporto


def gerar_administradores():
    """Cadastro interno de administradores: uma linha por aeroporto e início de vigência."""
    print("Administradores")
    pasta = DATA / "cadastros/administradores"
    pasta.mkdir(parents=True, exist_ok=True)
    texto = (DATA / "cadastros/aerodromos/AerodromosPublicos_2026-11-15.csv").read_bytes().decode("cp1252")
    leitor = csv.reader(io.StringIO(texto.split("\n", 1)[1]), delimiter=";")
    next(leitor)
    aerodromos = sorted({linha[0] for linha in leitor if linha})
    concedidos = concessoes()
    fonte_anac = "ANAC, Concessoes_Aeroportos.csv"
    linhas = []
    for icao in aerodromos:
        if icao in ANTES_OUTUBRO:
            nome, tipo = ANTES_OUTUBRO[icao]
            inicio = concedidos[icao][1] if icao in concedidos else "1900-01-01"
            linhas.append([icao, nome, tipo, inicio, fonte_anac if icao in concedidos else "Prefeitura de Caxias do Sul"])
        elif icao in concedidos:
            nome, inicio, contrato = concedidos[icao]
            linhas.append([icao, nome, "Concessão federal", inicio, f"{fonte_anac}, contrato {contrato}"])
        else:
            linhas.append([icao, "Não concedido", "Pública", "1900-01-01", "sem contrato de concessão na ANAC"])
    cabecalho = ["icao", "administrador", "tipo_administracao", "vigente_desde", "fonte"]
    for nome, extras in [("administradores_2026-09-30.csv", []),
                         ("administradores_2026-10-31.csv", [list(m) for m in MUDANCAS_OUTUBRO])]:
        with open(pasta / nome, "w", encoding="utf-8", newline="") as f:
            escritor = csv.writer(f, delimiter=";")
            escritor.writerow(cabecalho)
            escritor.writerows(linhas + extras)
        print(f"  {nome}: {len(linhas) + len(extras)} linhas")


def gerar_aeroportos_exterior():
    """Aeroportos do exterior que aparecem no VRA, a partir do OurAirports (domínio público)."""
    print("Aeroportos do exterior")
    tmp = DATA / ".ourairports"
    ok = baixar(f"{OURAIRPORTS}/airports.csv", tmp / "airports.csv") and \
        baixar(f"{OURAIRPORTS}/countries.csv", tmp / "countries.csv")
    if not ok:
        return
    codigos = set()
    for arquivo in (DATA / "vra").glob("VRA_*.csv"):
        for linha in arquivo.read_text(encoding="utf-8-sig").splitlines()[2:]:
            partes = linha.split(";")
            codigos.update({partes[4].strip('"'), partes[5].strip('"')})
    exterior = {c for c in codigos if c[:2] not in PREFIXOS_BRASIL}
    paises = {}
    with open(tmp / "countries.csv", encoding="utf-8") as f:
        for linha in csv.DictReader(f):
            paises[linha["code"]] = (linha["name"], linha["continent"])
    saida = []
    with open(tmp / "airports.csv", encoding="utf-8") as f:
        for linha in csv.DictReader(f):
            icao = linha.get("icao_code") or linha["ident"]
            if icao in exterior and icao not in {s[0] for s in saida}:
                pais, continente = paises.get(linha["iso_country"], ("", ""))
                saida.append([icao, linha["name"], linha["municipality"], linha["iso_country"], pais, continente,
                              linha["latitude_deg"], linha["longitude_deg"]])
    destino = DATA / "cadastros/aeroportos_exterior/aeroportos_exterior.csv"
    destino.parent.mkdir(parents=True, exist_ok=True)
    with open(destino, "w", encoding="utf-8", newline="") as f:
        escritor = csv.writer(f, delimiter=";")
        escritor.writerow(["icao", "nome", "cidade", "codigo_pais", "pais", "continente", "latitude", "longitude"])
        escritor.writerows(sorted(saida))
    faltando = exterior - {s[0] for s in saida}
    print(f"  {len(saida)} aeroportos; sem correspondência no OurAirports: {sorted(faltando)}")


if __name__ == "__main__":
    baixar_vra()
    baixar_cadastros()
    gerar_administradores()
    gerar_aeroportos_exterior()
    if not (DATA / "vra" / "VRA_202610.csv").exists():
        print("\nAtenção: outubro de 2026 ainda não foi publicado pela ANAC. Rode o script de novo depois da "
              "publicação (em geral, perto do dia 28 do mês seguinte).", file=sys.stderr)
