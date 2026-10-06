# Week 2 — Output-stationary Systolic Array: 행렬곱을 MAC 격자로

> 목표: `rtl/systolic.sv`가 **왜 이렇게 생겼는지**(skew, 제어 신호, done 타이밍)를 표로 설명하고,
> PPA 수치로 "systolic array는 왜 커져도 느려지지 않는가"를 답할 수 있다.

---

## 1. AI 관점 — 행렬곱 하나를 MAC 격자에 펼친다

`C = A × B` (A: R×K, B: K×C) → `C[i][j] = Σ_k A[i][k] · B[k][j]`

| | MAC 1개 (`mac`) | R×C systolic array |
|---|---|---|
| cycle당 MAC | 1 | R·C |
| cycle당 외부 입력 | 2개 (a, b) | R + C개 (A 열 하나 + B 행 하나) |
| 입력 1개당 재사용 | 1번 | A 원소는 C번, B 원소는 R번 |

→ 8×8이면 cycle당 64 MAC을 16개 입력으로 처리합니다. **데이터 재사용**이 핵심이고, 이게 memory wall을 줄이는 방법입니다.

## 2. Architecture 관점 — 무엇을 PE에 "세워 두는가" (dataflow)

| Dataflow | PE에 고정 | 흐르는 것 | 예 |
|---|---|---|---|
| **Output-stationary (이 repo)** | C[i][j] (누산기) | A → 오른쪽, B → 아래 | 누산기가 PE 안에 있어서 `mac`을 그대로 재사용 |
| Weight-stationary | B (weight) | A → 오른쪽, 부분합 → 아래 | Google TPU v1 |
| Input-stationary | A | B, 부분합 | |

## 3. RTL 관점 — skew와 타이밍

### 3.1 왜 skew가 필요한가
A[i][k]는 PE(i,0)에서 출발해 오른쪽으로 **j칸**, B[k][j]는 PE(0,j)에서 출발해 아래로 **i칸** 이동합니다.
두 값이 PE(i,j)에서 같은 cycle에 만나려면 행 i는 **i cycle**, 열 j는 **j cycle** 늦게 넣어야 합니다 (`delay_line`).

### 3.2 2×2, K=2 cycle 표 (edge 0에 k=0, edge 1에 k=1을 샘플)

| edge | PE(0,0) | PE(0,1) | PE(1,0) | PE(1,1) | done |
|---|---|---|---|---|---|
| 0 | A00·B00 (clr) | | | | 0 |
| 1 | + A01·B10 | A00·B01 (clr) | A10·B00 (clr) | | 0 |
| 2 | | + A01·B11 | + A11·B10 | A10·B01 (clr) | 0 |
| 3 | | | | + A11·B11 | **1** |

- PE(i,j)는 k를 edge **+(i+j)**에 누산합니다. 대각선으로 퍼지는 "파면(wavefront)"입니다.
- 마지막 k는 edge +(R+C−2)에 PE(R−1,C−1)에 도착합니다. `done`은 `in_last`를 R+C−1단 shift register로 늦춘 것이라 **정확히 그 edge에** 올라갑니다.

### 3.3 제어 신호는 데이터와 함께 이동한다
`en`(=in_valid)과 `clr`(=in_first)는 A와 같은 레지스터를 타고 오른쪽으로 갑니다.
그래서 bubble(in_valid=0)이나 새 행렬의 시작이 **자기 데이터와 같은 time slot에** 각 PE에 도착합니다. 중앙 제어기가 PE마다 신호를 따로 계산할 필요가 없습니다.
- `clr = in_valid & in_first`: valid가 아닌 cycle의 in_first는 무시해야 합니다. 이 AND를 빼면 TB에서 1808건 FAIL이 납니다.

### 3.4 처리량
행렬 하나(K) = K edge 입력 + (R+C−2) edge 배출 → 다음 행렬은 done 바로 다음 edge부터 시작할 수 있습니다.
이용률 = K / (K + R + C − 1). 예: 8×8, K=64 → 64/79 = **81%**

## 4. 검증 — TB가 무엇을 보장하나

| 항목 | 방법 |
|---|---|
| 정답 모델 | `C = A×B`를 k 순서로 누산. SAT=0은 ACC_W wrap, SAT=1은 매 단계 saturate (하드웨어를 흉내 내지 않고 산술 정의로) |
| 경계값 | K=1 (clr와 last가 같은 k), 전부 −128, 전부 127, −128×127 |
| 무작위 | 200개 행렬, K=1..64, bubble 무작위 삽입 (bubble 동안 in_first/in_last도 무작위 → 무시되는지 확인) |
| 타이밍 | done이 **정확히** R+C−2 edge 뒤에 오는지, 다음 행렬을 가장 빠른 시점에 시작 |
| 설정 | 2×2, 4×4, 8×8, 2×8, 8×2, 3×5, ACC_W=16 SAT=0/1, IN_W=4 |
| 버그 주입 | B skew 제거 → 2412건 FAIL, clr AND 제거 → 1808건 FAIL, done 1 edge 빠르게 → 405건 FAIL |

## 5. 반도체 관점 — sky130 합성 결과 (pre-P&R 추정)

`scripts/systolic_sweep.sh` (Yosys → sky130_fd_sc_hd tt 25°C 1.8V, ABC timing-driven, FF 오버헤드 500ps 가정)

### 배열 크기 (INT8, ACC_W=32)
| array | IN_W | ACC_W | cells | FFs | area (um2) | um2/PE | fmax (MHz) | delay (ps) | peak GOPS |
|---|---|---|---|---|---|---|---|---|---|
| 2x2 | 8 | 32 | 2421 | 183 | 20563 | 5141 | 115 | 8192 | 0.9 |
| 4x4 | 8 | 32 | 9843 | 819 | 84136 | 5258 | 114 | 8252 | 3.6 |
| 8x8 | 8 | 32 | 39374 | 3435 | 341107 | 5330 | 117 | 8060 | 15.0 |
| 16x16 | 8 | 32 | 160343 | 14043 | 1376809 | 5378 | 113 | 8349 | 57.9 |

### 정밀도 (4×4, ACC_W = 2·IN_W + 16)
| array | IN_W | ACC_W | cells | FFs | area (um2) | um2/PE | fmax (MHz) | delay (ps) | peak GOPS |
|---|---|---|---|---|---|---|---|---|---|
| 4x4 | 4 | 24 | 4278 | 547 | 39329 | 2458 | 159 | 5771 | 5.1 |
| 4x4 | 8 | 32 | 9843 | 819 | 84136 | 5258 | 114 | 8252 | 3.6 |
| 4x4 | 16 | 48 | 28864 | 1363 | 231618 | 14476 | 72 | 13433 | 2.3 |

### 해석
- **면적 ∝ PE 수**: PE당 면적이 크기와 상관없이 거의 일정합니다.
- **Fmax가 배열 크기와 무관**: critical path가 PE 하나 안(`a*b + acc` → acc FF)에 있고, PE 사이에는 이웃 간 레지스터 연결만 있기 때문입니다. 이게 systolic 구조의 핵심 장점입니다. 전역 배선(broadcast)이 없습니다.
- **처리량 ∝ N²**: 그래서 peak GOPS가 PE 수에 비례해서 늘어납니다.
- **정밀도**: INT4 / INT8 / INT16의 PE당 면적이 2458 / 5258 / 14476 µm²입니다 (곱셈기 ∝ 비트폭²). critical path도 짧아져서 Fmax가 159 / 114 / 72MHz입니다. 면적당 처리량은 **INT4 ≈ 130, INT8 ≈ 43, INT16 ≈ 10 GOPS/mm²**로, 비트폭을 절반으로 줄이면 면적과 속도에서 **두 번 이득**을 봅니다. 양자화(INT8/INT4)가 AI 가속기에서 중요한 이유입니다.

### 한계 (다음 단계 후보)
| 한계 | 왜 문제인가 | 해결 방향 |
|---|---|---|
| PE(0,0)가 포트에서 바로 입력을 받음 | 칩 외부 지연이 critical path에 더해짐 | 입력 레지스터 추가 |
| 출력 `c`가 R·C·32비트 병렬 버스 | 16×16이면 8192비트, 실제 칩에서는 불가능 | 행/열 단위로 밀어 내보내는 shift-out |
| 버퍼·제어기 없음 | 행렬을 TB가 직접 공급 | SRAM 버퍼 + 제어 FSM (README stage 5, 6) |
| 배선·클럭 트리 미반영 | 실제 Fmax는 더 낮음 | OpenROAD P&R (W3) |
| PE의 critical path = 곱셈 + 누산 | Fmax 약 115MHz | mac_pipe / mac_csa로 PE 교체 실험 |

## 6. 면접용 한 줄 답
> "R×C output-stationary systolic array를 직접 설계해서, 2×2에서 16×16까지 sky130으로 합성했습니다. PE당 면적은 약 5.2k µm²로 일정했고, Fmax는 크기와 상관없이 약 115MHz였습니다. critical path가 PE 안에만 있고 PE 사이에는 이웃 연결만 있어서, 처리량은 PE 수에 비례해 늘지만 클럭은 떨어지지 않습니다."

## 7. 확인 질문
1. 3×5 배열에서 k=0이 PE(2,4)에 도착하는 edge는? done은 마지막 k 뒤 몇 edge에 올라가나?
2. B의 skew를 빼면 PE(1,1)에서는 어떤 A와 B가 곱해지나? (2×2 cycle 표로)
3. 8×8, K=8이면 이용률은? K가 작은 레이어(예: depthwise conv)가 systolic array에 불리한 이유는?
