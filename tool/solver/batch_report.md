# TexasSolver calibration batch

Spots solved: 30  ·  maxPerBucket=3  ·  totalCap=30

**Realized equity:** `R = (EV_GTO + C_hero) / pot`, `EQR_emp = R / rawEq` (net-chip EV frame, verified by regression; uses each spot's actual committed chips). Compare **EQR_emp** to the DCE multiplier — that is the calibration target. R>1 = over-realization (wins future bets); R<0 clamped at 0 in reading. Loose convergence (3-4.5% expl.) → treat as directional, not final values.

## Per-bucket calibration (DCE vs solver)

EQR_emp = total realization (incl. fold equity); **EQR_show = showdown realization only (check/call line, NO fold equity) — the right target for the bluff-catch EQR multiplier.**

| Bucket (handClass/pos) | n | avg raw eq | **DCE mult** | EQR_emp (total) | **EQR_show (no-FE)** | avg EV gap |
|---|---|---|---|---|---|---|
| air/IP | 3 | 0.42 | 0.30 | 1.49 | 1.27 | 13.53 |
| air/OOP | 3 | 0.22 | 0.10 | 0.15 | 0.13 | 11.22 |
| marginalMade/IP | 3 | 0.75 | 0.92 | 1.30 | 1.23 | 8.19 |
| marginalMade/OOP | 3 | 0.64 | 0.79 | 0.87 | 0.94 | 20.33 |
| strongDraw/IP | 3 | 0.49 | 1.00 | 1.62 | 1.09 | 27.73 |
| strongDraw/OOP | 3 | 0.47 | 0.88 | 0.90 | 0.78 | 4.29 |
| strongMade/IP | 3 | 0.86 | 1.17 | 1.35 | 1.09 | 38.80 |
| strongMade/OOP | 3 | 0.70 | 1.12 | 1.20 | 1.19 | 5.96 |
| weakDraw/IP | 3 | 0.42 | 0.88 | 1.58 | 0.96 | 15.63 |
| weakDraw/OOP | 3 | 0.38 | 0.78 | 0.25 | 0.16 | 9.08 |

## Per-spot detail

| id | bucket | board | hero | SPR | raw | DCE mult | EQR_emp | EQR_show | GTO top | EV gap |
|---|---|---|---|---|---|---|---|---|---|---|
| pluribus-102b-76-p5 | air/IP | 6h 6s 5s | JdKc | 19.55 | 0.42 | 0.30 | 1.41 | 1.22 | BET 250.000000 | 7.70 |
| pluribus-112b-158-p4 | air/IP | 5s 8s 6d | JdKs | 19.55 | 0.29 | 0.30 | 1.58 | 1.37 | BET 250.000000 | 1.10 |
| pluribus-112b-97-p5 | air/IP | 3h 4d 4h | Ah8c | 17.73 | 0.56 | 0.30 | 1.48 | 1.22 | BET 275.000000 | 31.80 |
| pluribus-103b-103-p2 | air/OOP | Ah 5c 8s | QsTd | 21.78 | 0.17 | 0.10 | -0.32 | -0.30 | CHECK | 27.26 |
| pluribus-103b-164-p2 | air/OOP | 7d Jc 5c | Ks6c | 17.73 | 0.30 | 0.10 | -0.15 | -0.13 | CHECK | 6.20 |
| pluribus-103b-69-p1 | air/OOP | Ad 2c 4d | TcJc | 16.17 | 0.20 | 0.10 | 0.93 | 0.83 | BET 300.000000 | 0.20 |
| pluribus-100b-113-p5 | marginalMade/IP | Th Ac 6d | JdJc | 20.83 | 0.65 | 0.92 | 1.28 | 1.18 | BET 235.000000 | 12.58 |
| pluribus-111b-83-p6 | marginalMade/IP | Ad 6s 4d | TdAs | 19.55 | 0.83 | 0.92 | 1.26 | 1.17 | BET 250.000000 | 1.79 |
| pluribus-114b-75-p4 | marginalMade/IP | 5d 3h 9c | AdAs | 21.78 | 0.76 | 0.92 | 1.38 | 1.35 | BET 225.000000 | 10.19 |
| pluribus-100b-92-p2 | marginalMade/OOP | Kh 3s Ah | 2hAs | 17.73 | 0.76 | 0.79 | 0.96 | 1.03 | CHECK | 43.35 |
| pluribus-102b-95-p2 | marginalMade/OOP | 2h Kd Ad | JdKc | 20.83 | 0.46 | 0.79 | 0.77 | 0.88 | CHECK | 15.05 |
| pluribus-103b-93-p1 | marginalMade/OOP | Td Qd 3h | 9cQc | 17.77 | 0.71 | 0.79 | 0.90 | 0.91 | BET 275.000000 | 2.59 |
| pluribus-103b-75-p2 | strongDraw/IP | 6h 4d 7h | Js5s | 16.17 | 0.39 | 1.00 | 1.51 | 1.05 | BET 300.000000 | 64.66 |
| pluribus-94b-49-p3 | strongDraw/IP | Jd 9h 5h | Ah6h | 20.83 | 0.55 | 1.00 | 1.70 | 1.08 | BET 235.000000 | 15.95 |
| pluribus-97b-148-p3 | strongDraw/IP | 7d Jd 9c | Ad3d | 19.55 | 0.53 | 1.00 | 1.66 | 1.16 | BET 250.000000 | 2.57 |
| pluribus-103b-115-p2 | strongDraw/OOP | 9s 5s 7s | 8sTc | 19.55 | 0.53 | 0.88 | 1.10 | 0.90 | BET 250.000000 | 5.37 |
| pluribus-45b-123-p1 | strongDraw/OOP | 9h Td 8d | JcAh | 16.17 | 0.48 | 0.88 | 0.46 | 0.47 | BET 300.000000 | 7.34 |
| pluribus-45b-145-p1 | strongDraw/OOP | 9d 6d Qc | Tc8d | 19.50 | 0.39 | 0.88 | 1.15 | 0.95 | BET 250.000000 | 0.14 |
| pluribus-102b-98-p4 | strongMade/IP | Ah Ad 7s | KsKc | 17.73 | 0.75 | 1.30 | 1.05 | 1.04 | BET 275.000000 | 11.30 |
| pluribus-112b-104-p3 | strongMade/IP | As Qd 8s | AhAc | 19.55 | 0.93 | 1.08 | 1.26 | 1.03 | BET 250.000000 | 27.71 |
| pluribus-41b-124-p2 | strongMade/IP | 6c Qc 9c | 8c2c | 16.17 | 0.89 | 1.13 | 1.74 | 1.21 | BET 300.000000 | 77.37 |
| pluribus-100b-81-p4 | strongMade/OOP | Th Ts As | AdQc | 16.29 | 0.68 | 1.12 | 1.00 | 0.99 | BET 300.000000 | 4.78 |
| pluribus-102b-92-p2 | strongMade/OOP | 2s 8h 2c | 8cTd | 17.73 | 0.70 | 1.12 | 1.28 | 1.28 | BET 275.000000 | 3.54 |
| pluribus-111b-174-p2 | strongMade/OOP | 7h Th 9c | 9d7c | 17.73 | 0.72 | 1.12 | 1.34 | 1.32 | BET 275.000000 | 9.56 |
| pluribus-100b-117-p6 | weakDraw/IP | Qc 9c Ks | AcJh | 15.00 | 0.42 | 0.88 | 0.80 | 0.59 | BET 325.000000 | 25.71 |
| pluribus-102b-103-p3 | weakDraw/IP | 2h Jh 8h | ThAc | 20.83 | 0.53 | 0.88 | 1.49 | 1.24 | BET 235.000000 | 12.18 |
| pluribus-102b-89-p5 | weakDraw/IP | 9s Th 8h | QhKc | 18.83 | 0.31 | 0.88 | 2.47 | 1.04 | BET 260.000000 | 9.01 |
| pluribus-103b-173-p2 | weakDraw/OOP | Ks Th 5h | 6h9h | 17.73 | 0.37 | 0.78 | 0.08 | -0.00 | BET 275.000000 | 15.24 |
| pluribus-113b-74-p2 | weakDraw/OOP | 2h 7h 8s | 9hJd | 19.55 | 0.27 | 0.78 | 0.15 | -0.05 | BET 250.000000 | 7.92 |
| pluribus-40b-140-p2 | weakDraw/OOP | 3d 4s 8s | Ad5s | 19.55 | 0.50 | 0.78 | 0.54 | 0.55 | BET 250.000000 | 4.09 |

## Coverage

Buckets discovered: 10 ([air/IP, air/OOP, marginalMade/IP, marginalMade/OOP, strongDraw/IP, strongDraw/OOP, strongMade/IP, strongMade/OOP, weakDraw/IP, weakDraw/OOP]).
- marginalMade/IP: 19 available, capped at 3.
- weakDraw/IP: 10 available, capped at 3.
- strongMade/OOP: 9 available, capped at 3.
- marginalMade/OOP: 47 available, capped at 3.
- air/IP: 17 available, capped at 3.
- strongMade/IP: 9 available, capped at 3.
- air/OOP: 27 available, capped at 3.
- strongDraw/OOP: 8 available, capped at 3.
- weakDraw/OOP: 12 available, capped at 3.
