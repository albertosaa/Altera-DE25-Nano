"""Gera uma ilustração vetorial funcional do RTL 7x7; não exporta o Quartus.

Executar da raiz: python scripts/gerar_esquema_matrix7x7.py
O desenho descreve matrix7_mm.v e o mapeamento final confirmado no Fitter.
"""
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "img" / "matrix7x7"
OUT.mkdir(parents=True, exist_ok=True)
parts = ['''<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1100" viewBox="0 0 1600 1100">
<title>DE25-Nano: multiplicador inteiro paralelo 7 por 7</title>
<desc>Ilustração funcional do módulo matrix7_mm. Uma célula com sete produtos e três níveis de soma é replicada 49 vezes. Seis produtos por célula usam DSPs e um usa ALMs. Quatro estágios registrados a 100 MHz.</desc>
<defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0,0 L10,5 L0,10 Z" fill="#354655"/></marker></defs>
<rect width="1600" height="1100" fill="white"/>
<g font-family="DejaVu Sans, sans-serif" fill="#182b3b">
''']


def text(x, y, value, size=22, anchor="start", weight="normal", color="#182b3b"):
    parts.append(f'<text x="{x}" y="{y}" font-size="{size}" text-anchor="{anchor}" font-weight="{weight}" fill="{color}">{escape(value)}</text>')


def box(x, y, w, h, lines, fill="#edf4fa", size=22):
    parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{fill}" stroke="#354655" stroke-width="2"/>')
    spacing = size + 7
    first_y = y + h / 2 - (len(lines) - 1) * spacing / 2 + size * .34
    for n, line in enumerate(lines):
        text(x+w/2, first_y+n*spacing, line, size, "middle")


def edge(x1, y1, x2, y2, bend=None):
    if bend is None:
        d = f'M{x1},{y1} L{x2},{y2}'
    else:
        d = f'M{x1},{y1} H{bend} V{y2} H{x2}'
    parts.append(f'<path d="{d}" fill="none" stroke="#354655" stroke-width="2"/>')
    # Polígono explícito mantém a seta também em renderizadores SVG simples.
    parts.append(f'<polygon points="{x2},{y2} {x2-10},{y2-5} {x2-10},{y2+5}" fill="#354655"/>')


text(55, 53, "DE25-Nano · Multiplicação inteira paralela 7×7", 34, weight="bold")
text(55, 91, "Visão funcional do RTL e detalhe de uma das 49 células de saída", 23)
parts.append('<rect x="582" y="128" width="965" height="192" rx="12" fill="#fafcfe" stroke="#6e8293" stroke-width="2" stroke-dasharray="8 5"/>')
text(600, 154, "FPGA · matrix7_mm", 20, weight="bold")
box(45, 180, 235, 95, ["ARM / Linux", "C e comparação"], fill="#e7edf1")
box(325, 180, 220, 95, ["Ponte lightweight", "Avalon-MM · 32 bits"], size=20)
box(610, 180, 225, 95, ["Registradores A/B", "49 × 16 bits cada"], size=20)
box(895, 180, 230, 95, ["49 células paralelas", "4 estágios de cálculo"], size=20)
box(1185, 180, 325, 95, ["49 resultados C · 35 bits", "Leitura com sinal em 64 bits"], size=20)
for start, end in [(280, 325), (545, 610), (835, 895), (1125, 1185)]:
    edge(start, 227, end, 227)
parts.append('<path d="M1450,275 V306 H435 V275" fill="none" stroke="#354655" stroke-width="2"/><polygon points="435,275 430,285 440,285" fill="#354655"/>')
text(930, 301, "Leitura de resultados e estado", 18, anchor="middle")
text(55, 355, "Controle: START · DONE · busy · RUNS · CYCLES       Clock: 100 MHz       Latência: 4 ciclos = 40 ns nominais", 22)
parts.append('<line x1="55" y1="381" x2="1545" y2="381" stroke="#b7c4cf" stroke-width="2"/>')
text(55, 421, "Detalhe de C[i,j] = Σ A[i,k] × B[k,j], com k = 0…6", 28, weight="bold")
text(55, 453, "Entradas inteiras de 16 bits com sinal. A célula é replicada para i e j de 0 a 6. R indica registrador.", 21)

for x, header in [(100, "Ciclo 1 · produtos"), (535, "Ciclo 2 · pares"), (875, "Ciclo 3 · grupos"), (1230, "Ciclo 4 · saída")]:
    text(x, 499, header, 22, weight="bold")
ys = [550+60*k for k in range(7)]
for k, y in enumerate(ys):
    box(100, y-23, 325, 46, [f"p{k} = A[i,{k}] × B[{k},j]   | R32"],
        fill="#fff0d6" if k == 6 else "#e7f1fa", size=19)

pair_y = [580, 700, 820, 910]
for n, label in enumerate(["p0 + p1  | R33", "p2 + p3  | R33", "p4 + p5  | R33", "p6: extensão  | R33"]):
    box(535, pair_y[n]-24, 240, 48, [label], fill="#f0f4f6", size=20)
for k, y in enumerate(ys):
    port_y = pair_y[k//2] if k == 6 else pair_y[k//2] + (-9 if k % 2 == 0 else 9)
    edge(425, y, 535, port_y, bend=475 if k % 2 == 0 else 495)

box(875, 640-28, 235, 56, ["(p0+p1)+(p2+p3)", "R34"], fill="#f0f4f6", size=19)
box(875, 865-28, 235, 56, ["(p4+p5)+p6", "R34"], fill="#f0f4f6", size=19)
for n, y in enumerate(pair_y):
    port_y = (640 if n < 2 else 865) + (-12 if n % 2 == 0 else 12)
    edge(775, y, 875, port_y, bend=815 if n % 2 == 0 else 835)
box(1230, 718, 280, 94, ["Soma final → C[i,j]", "R35 · com sinal"], fill="#e8f3ec", size=23)
edge(1110, 640, 1230, 749, bend=1160)
edge(1110, 865, 1230, 781, bend=1180)

text(100, 970, "p0…p5: DSPs (3 blocos por célula)", 22, weight="bold")
text(790, 970, "p6: multiplicador em lógica programável (ALMs)", 22, weight="bold")
text(55, 1016, "Total: 343 produtos simultâneos · 147 DSPs · 49 multiplicadores em ALMs · sem reutilização entre termos", 23)
text(55, 1061, "Ilustração funcional derivada de matrix7_mm.v. Não é uma exportação do RTL Viewer nem um mapa físico de colocação.", 19, color="#506272")
parts.append('</g></svg>')
path = OUT / "esquema_funcional_7x7.svg"
path.write_text('\n'.join(parts)+'\n')
print(path)
