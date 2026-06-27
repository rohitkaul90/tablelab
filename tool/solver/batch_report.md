# TexasSolver calibration batch

Spots: 69 solved  ·  0 errored (excluded)  ·  maxPerBucket=6  ·  totalCap=72

**Realized equity:** `R = (EV_GTO + C_hero) / pot`, `EQR_emp = R / rawEq` (net-chip EV frame, verified by regression; uses each spot's actual committed chips). Compare **EQR_emp** to the DCE multiplier — that is the calibration target. R>1 = over-realization (wins future bets); R<0 clamped at 0 in reading. Loose convergence (3-4.5% expl.) → treat as directional, not final values.

## Per-bucket calibration (DCE vs solver)

EQR_emp = total realization (incl. fold equity); **EQR_show = showdown realization only (check/call line, NO fold equity) — the right target for the bluff-catch EQR multiplier.**

| Bucket (handClass/pos) | n | avg raw eq | **DCE mult** | EQR_emp (total) | **EQR_show (no-FE)** | EQR_show min–max | avg EV gap |
|---|---|---|---|---|---|---|---|
| air_hi/IP | 6 | 0.44 | 0.30 | 1.80 | 1.08 | 0.55–1.61 | 4.50 |
| air_hi/OOP | 6 | 0.39 | 0.10 | 0.05 | 0.08 | 0.00–0.27 | 2.49 |
| air_lo/IP | 6 | 0.24 | 0.30 | 1.88 | 0.91 | 0.00–1.60 | 1.53 |
| air_lo/OOP | 6 | 0.20 | 0.10 | 0.14 | 0.12 | 0.00–0.70 | 10.90 |
| marginalMade/IP | 6 | 0.69 | 0.92 | 1.35 | 1.18 | 1.01–1.50 | 6.06 |
| marginalMade/OOP | 6 | 0.60 | 0.79 | 0.76 | 0.74 | 0.42–0.94 | 1.29 |
| strongDraw/IP | 3 | 0.49 | 1.00 | 1.58 | 1.08 | 1.03–1.12 | 8.21 |
| strongDraw/OOP | 6 | 0.45 | 0.88 | 0.67 | 0.49 | 0.00–0.91 | 1.27 |
| strongMade/IP | 6 | 0.81 | 1.21 | 1.46 | 1.16 | 0.91–1.39 | 32.04 |
| strongMade/OOP | 6 | 0.76 | 1.12 | 1.67 | 1.53 | 0.98–2.27 | 2.89 |
| weakDraw/IP | 6 | 0.42 | 0.88 | 1.71 | 1.05 | 0.69–1.34 | 5.84 |
| weakDraw/OOP | 6 | 0.38 | 0.78 | 0.42 | 0.33 | 0.00–1.00 | 1.48 |

## Per-spot detail

| id | bucket | board | hero | SPR | raw | DCE mult | EQR_emp | EQR_show | GTO top | EV gap |
|---|---|---|---|---|---|---|---|---|---|---|
| pluribus-95b-85-p3 | air_hi/IP | Ks 8s Kh | AdJs | 20.83 | 0.54 | 0.30 | 1.72 | 1.13 | BET 235.000000 | 2.73 |
| pluribus-94b-80-p5 | air_hi/IP | 9d 2h Tc | JsAc | 17.77 | 0.31 | 0.30 | 1.02 | 0.55 | BET 275.000000 | 0.14 |
| pluribus-102b-76-p5 | air_hi/IP | 6h 6s 5s | JdKc | 19.55 | 0.42 | 0.30 | 2.01 | 1.61 | BET 250.000000 | 2.94 |
| pluribus-51b-111-p6 | air_hi/IP | 8c 4h 5d | TcQd | 17.73 | 0.31 | 0.30 | 3.02 | 0.98 | BET 275.000000 | 1.66 |
| pluribus-45b-99-p3 | air_hi/IP | 2c 2s Ks | AcQh | 19.55 | 0.51 | 0.30 | 1.57 | 1.03 | BET 250.000000 | 8.71 |
| pluribus-112b-97-p5 | air_hi/IP | 3h 4d 4h | Ah8c | 17.73 | 0.56 | 0.30 | 1.43 | 1.17 | BET 275.000000 | 10.81 |
| pluribus-113b-77-p2 | air_hi/OOP | 8c 8h 2s | Kc3c | 19.55 | 0.39 | 0.10 | 0.00 | 0.00 | BET 250.000000 | 1.52 |
| pluribus-45b-100-p2 | air_hi/OOP | Jh 3d 2c | QsAh | 21.78 | 0.50 | 0.10 | 0.20 | 0.20 | BET 225.000000 | 0.92 |
| pluribus-103b-98-p3 | air_hi/OOP | 3s 2h 5c | JsQs | 17.82 | 0.32 | 0.10 | 0.00 | 0.00 | BET 275.000000 | 0.39 |
| pluribus-111b-103-p2 | air_hi/OOP | 3c 8h 8d | KcJc | 19.55 | 0.32 | 0.10 | 0.09 | 0.27 | BET 250.000000 | 11.48 |
| pluribus-44b-58-p2 | air_hi/OOP | 2c 7h 6d | KhJs | 21.78 | 0.33 | 0.10 | 0.00 | 0.00 | CHECK | 0.36 |
| pluribus-42b-126-p5 | air_hi/OOP | 7h 4d 8d | AcKh | 17.82 | 0.48 | 0.10 | 0.00 | 0.00 | BET 275.000000 | 0.29 |
| pluribus-75b-148-p5 | air_lo/IP | 3s Jc 7c | As9s | 20.83 | 0.26 | 0.30 | 1.95 | 1.60 | BET 235.000000 | 0.09 |
| pluribus-75b-111-p3 | air_lo/IP | 7s 4c 5d | Th9h | 19.55 | 0.24 | 0.30 | 2.56 | 0.84 | BET 250.000000 | 0.12 |
| pluribus-51b-125-p6 | air_lo/IP | Js Ac Kd | 6d8d | 17.82 | 0.11 | 0.30 | 0.00 | 0.00 | CHECK | 4.29 |
| pluribus-76b-56-p6 | air_lo/IP | 6s 9h 5s | KcTc | 15.00 | 0.26 | 0.30 | 1.89 | 0.66 | BET 325.000000 | 4.32 |
| pluribus-112b-158-p4 | air_lo/IP | 5s 8s 6d | JdKs | 19.55 | 0.29 | 0.30 | 1.53 | 1.37 | BET 250.000000 | 0.23 |
| pluribus-44b-51-p4 | air_lo/IP | 7d 6h Ts | JhQh | 21.78 | 0.28 | 0.30 | 3.34 | 0.96 | BET 225.000000 | 0.13 |
| pluribus-103b-69-p1 | air_lo/OOP | Ad 2c 4d | TcJc | 16.17 | 0.20 | 0.10 | 0.86 | 0.70 | BET 300.000000 | 1.93 |
| pluribus-103b-103-p2 | air_lo/OOP | Ah 5c 8s | QsTd | 21.78 | 0.17 | 0.10 | 0.00 | 0.00 | CHECK | 24.54 |
| pluribus-112b-98-p2 | air_lo/OOP | 3s Td Th | Ks8s | 19.55 | 0.18 | 0.10 | 0.00 | 0.00 | CHECK | 1.20 |
| pluribus-103b-164-p2 | air_lo/OOP | 7d Jc 5c | Ks6c | 17.73 | 0.30 | 0.10 | 0.00 | 0.00 | CHECK | 3.38 |
| pluribus-113b-83-p2 | air_lo/OOP | Js 7h 7c | 5hAc | 20.83 | 0.19 | 0.10 | 0.00 | 0.00 | CHECK | 33.68 |
| pluribus-114b-135-p2 | air_lo/OOP | 4h Ah 7d | 9hJc | 21.78 | 0.17 | 0.10 | 0.00 | 0.00 | CHECK | 0.65 |
| pluribus-45b-106-p6 | marginalMade/IP | Jh Ad Ts | QdJd | 17.73 | 0.72 | 0.92 | 1.16 | 1.01 | BET 275.000000 | 2.76 |
| pluribus-44b-91-p6 | marginalMade/IP | Th 4h 6h | 9cTs | 21.78 | 0.46 | 0.92 | 2.01 | 1.50 | BET 225.000000 | 20.15 |
| pluribus-111b-83-p6 | marginalMade/IP | Ad 6s 4d | TdAs | 19.55 | 0.83 | 0.92 | 1.33 | 1.20 | BET 250.000000 | 0.96 |
| pluribus-100b-113-p5 | marginalMade/IP | Th Ac 6d | JdJc | 20.83 | 0.65 | 0.92 | 1.25 | 1.15 | BET 235.000000 | 7.58 |
| pluribus-114b-75-p4 | marginalMade/IP | 5d 3h 9c | AdAs | 21.78 | 0.76 | 0.92 | 1.24 | 1.19 | BET 225.000000 | 2.98 |
| pluribus-114b-94-p6 | marginalMade/IP | 5c Qh Ts | JcTh | 16.21 | 0.72 | 0.92 | 1.09 | 1.03 | BET 300.000000 | 1.93 |
| pluribus-103b-93-p1 | marginalMade/OOP | Td Qd 3h | 9cQc | 17.77 | 0.71 | 0.79 | 0.91 | 0.89 | BET 275.000000 | 0.85 |
| pluribus-111b-101-p1 | marginalMade/OOP | Jc 6h 9h | Kd9c | 17.68 | 0.52 | 0.79 | 0.89 | 0.88 | BET 275.000000 | 0.75 |
| pluribus-102b-95-p2 | marginalMade/OOP | 2h Kd Ad | JdKc | 20.83 | 0.46 | 0.79 | 0.80 | 0.80 | CHECK | 1.01 |
| pluribus-111b-81-p2 | marginalMade/OOP | 4h 5h Qc | Qs8h | 17.73 | 0.57 | 0.79 | 0.57 | 0.50 | BET 275.000000 | 2.15 |
| pluribus-100b-92-p2 | marginalMade/OOP | Kh 3s Ah | 2hAs | 17.73 | 0.76 | 0.79 | 0.95 | 0.94 | CHECK | 0.80 |
| pluribus-111b-89-p2 | marginalMade/OOP | 8h Jc Qc | Kd8s | 19.55 | 0.55 | 0.79 | 0.43 | 0.42 | CHECK | 2.16 |
| pluribus-97b-148-p3 | strongDraw/IP | 7d Jd 9c | Ad3d | 19.55 | 0.53 | 1.00 | 1.57 | 1.08 | BET 250.000000 | 4.56 |
| pluribus-103b-75-p2 | strongDraw/IP | 6h 4d 7h | Js5s | 16.17 | 0.39 | 1.00 | 1.53 | 1.12 | BET 300.000000 | 0.05 |
| pluribus-94b-49-p3 | strongDraw/IP | Jd 9h 5h | Ah6h | 20.83 | 0.55 | 1.00 | 1.65 | 1.03 | BET 235.000000 | 20.01 |
| pluribus-45b-123-p1 | strongDraw/OOP | 9h Td 8d | JcAh | 16.17 | 0.48 | 0.88 | 0.43 | 0.42 | BET 300.000000 | 3.58 |
| pluribus-45b-145-p1 | strongDraw/OOP | 9d 6d Qc | Tc8d | 19.50 | 0.39 | 0.88 | 1.12 | 0.72 | BET 250.000000 | 0.25 |
| pluribus-53b-180-p2 | strongDraw/OOP | 6d Js Td | 8h9s | 21.78 | 0.33 | 0.88 | 0.12 | 0.00 | BET 225.000000 | 1.03 |
| pluribus-103b-115-p2 | strongDraw/OOP | 9s 5s 7s | 8sTc | 19.55 | 0.53 | 0.88 | 1.12 | 0.91 | BET 250.000000 | 0.08 |
| pluribus-76b-62-p2 | strongDraw/OOP | 6h Qs Ts | 9dJs | 19.55 | 0.47 | 0.88 | 0.78 | 0.58 | CHECK | 0.45 |
| pluribus-77b-48-p2 | strongDraw/OOP | 3s 3c Tc | 8cAc | 21.78 | 0.48 | 0.88 | 0.48 | 0.31 | BET 225.000000 | 2.21 |
| pluribus-41b-124-p2 | strongMade/IP | 6c Qc 9c | 8c2c | 16.17 | 0.89 | 1.13 | 1.79 | 1.14 | BET 300.000000 | 169.79 |
| pluribus-112b-104-p3 | strongMade/IP | As Qd 8s | AhAc | 19.55 | 0.93 | 1.08 | 1.32 | 1.03 | BET 250.000000 | 3.50 |
| pluribus-102b-98-p4 | strongMade/IP | Ah Ad 7s | KsKc | 17.73 | 0.75 | 1.30 | 0.96 | 0.91 | BET 275.000000 | 8.19 |
| pluribus-75b-80-p2 | strongMade/IP | 7s 7c Kh | 3sKs | 19.50 | 0.77 | 1.30 | 1.48 | 1.35 | BET 250.000000 | 5.38 |
| pluribus-77b-72-p3 | strongMade/IP | Kh Kc 6h | 9h9s | 21.78 | 0.65 | 1.30 | 1.38 | 1.14 | BET 225.000000 | 0.61 |
| pluribus-94b-105-p6 | strongMade/IP | 8s Jd Qs | Ts9c | 19.55 | 0.89 | 1.13 | 1.84 | 1.39 | BET 250.000000 | 4.80 |
| pluribus-44b-118-p2 | strongMade/OOP | Jc 9s 2h | 2s2d | 21.78 | 0.88 | 1.12 | 2.52 | 2.27 | BET 225.000000 | 1.97 |
| pluribus-111b-174-p2 | strongMade/OOP | 7h Th 9c | 9d7c | 17.73 | 0.72 | 1.12 | 1.30 | 1.23 | BET 275.000000 | 1.09 |
| pluribus-51b-102-p1 | strongMade/OOP | Ks 3s 5d | 5sAs | 14.88 | 0.70 | 1.12 | 2.03 | 1.72 | BET 325.000000 | 0.74 |
| pluribus-102b-92-p2 | strongMade/OOP | 2s 8h 2c | 8cTd | 17.73 | 0.70 | 1.12 | 1.32 | 1.29 | BET 275.000000 | 0.79 |
| pluribus-76b-84-p2 | strongMade/OOP | Kc Qh 3s | Kh3h | 19.55 | 0.88 | 1.12 | 1.79 | 1.70 | BET 250.000000 | 12.66 |
| pluribus-100b-81-p4 | strongMade/OOP | Th Ts As | AdQc | 16.29 | 0.68 | 1.12 | 1.02 | 0.98 | BET 300.000000 | 0.06 |
| pluribus-112b-92-p5 | weakDraw/IP | 9s Qc Ks | ThAs | 20.83 | 0.46 | 0.88 | 1.24 | 0.93 | BET 235.000000 | 10.56 |
| pluribus-44b-61-p5 | weakDraw/IP | Js 9s 8c | AhQs | 21.78 | 0.48 | 0.88 | 1.32 | 0.92 | BET 225.000000 | 2.03 |
| pluribus-50b-114-p4 | weakDraw/IP | 9c Kh 2d | QcTd | 21.78 | 0.34 | 0.88 | 2.48 | 1.33 | BET 225.000000 | 2.37 |
| pluribus-102b-89-p5 | weakDraw/IP | 9s Th 8h | QhKc | 18.83 | 0.31 | 0.88 | 2.70 | 1.06 | BET 260.000000 | 3.45 |
| pluribus-102b-103-p3 | weakDraw/IP | 2h Jh 8h | ThAc | 20.83 | 0.53 | 0.88 | 1.66 | 1.34 | BET 235.000000 | 16.30 |
| pluribus-100b-117-p6 | weakDraw/IP | Qc 9c Ks | AcJh | 15.00 | 0.42 | 0.88 | 0.90 | 0.69 | BET 325.000000 | 0.34 |
| pluribus-113b-74-p2 | weakDraw/OOP | 2h 7h 8s | 9hJd | 19.55 | 0.27 | 0.78 | 0.04 | 0.00 | BET 250.000000 | 1.91 |
| pluribus-42b-127-p2 | weakDraw/OOP | 2d 5d Td | 9dQc | 21.78 | 0.32 | 0.78 | 0.69 | 0.51 | BET 225.000000 | 0.06 |
| pluribus-44b-102-p2 | weakDraw/OOP | 5s 4s 5c | 9sQs | 21.78 | 0.53 | 0.78 | 1.12 | 1.00 | BET 225.000000 | 0.46 |
| pluribus-103b-173-p2 | weakDraw/OOP | Ks Th 5h | 6h9h | 17.73 | 0.37 | 0.78 | 0.09 | 0.00 | BET 275.000000 | 4.30 |
| pluribus-51b-172-p2 | weakDraw/OOP | 9c Td 2d | 6d7h | 19.79 | 0.30 | 0.78 | 0.03 | 0.00 | CHECK | 1.63 |
| pluribus-40b-140-p2 | weakDraw/OOP | 3d 4s 8s | Ad5s | 19.55 | 0.50 | 0.78 | 0.54 | 0.45 | BET 250.000000 | 0.55 |

## Coverage

Buckets discovered: 12 ([air_hi/IP, air_hi/OOP, air_lo/IP, air_lo/OOP, marginalMade/IP, marginalMade/OOP, strongDraw/IP, strongDraw/OOP, strongMade/IP, strongMade/OOP, weakDraw/IP, weakDraw/OOP]).
- marginalMade/IP: 19 available, capped at 6.
- weakDraw/IP: 10 available, capped at 6.
- strongMade/OOP: 9 available, capped at 6.
- marginalMade/OOP: 47 available, capped at 6.
- air_hi/IP: 8 available, capped at 6.
- strongMade/IP: 9 available, capped at 6.
- air_lo/OOP: 18 available, capped at 6.
- strongDraw/OOP: 8 available, capped at 6.
- weakDraw/OOP: 12 available, capped at 6.
- air_hi/OOP: 9 available, capped at 6.
- air_lo/IP: 9 available, capped at 6.
