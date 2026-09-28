# Week 1 · Day 1 — MAC 하나로 AI → Architecture → RTL → 반도체 → 논문 연결하기

> 오늘의 목표: **INT8 MAC을 직접 만들고, 그 MAC이 왜 AI 반도체의 기본 단위인지 설명할 수 있다.**
> 예상 소요: 3~4시간

---

## 1. AI 관점 — 왜 MAC인가 (20분)

Linear layer: \(y = Wx\)  →  출력 하나는 \(y_j = \sum_i w_{ji} x_i\)

즉 **곱하고(Multiply) 더한다(Accumulate)** 의 반복. CNN의 convolution도, Transformer의 \(QK^T\), \(AV\), FFN도 결국 전부 행렬곱 = MAC의 반복입니다.

- GPT류 모델 FLOPs의 대부분 = 행렬곱
- 그래서 AI accelerator 설계 = "MAC을 얼마나 많이, 얼마나 싸게(에너지/면적), 얼마나 쉬지 않고(데이터 공급) 돌리느냐"

**스스로 답해보기:** 4096×4096 행렬과 4096 벡터 곱에는 MAC이 몇 번 필요한가? (답: 약 16.7M)

## 2. Architecture 관점 — MAC을 여러 개 놓으면 (20분)

```
MAC 1개        → 1 MAC/cycle
MAC N×N 배열   → N² MAC/cycle   ← Systolic array (Week 2)
```

문제는 연산이 아니라 **데이터 공급**입니다. MAC 하나에 매 cycle 입력 2개(a, b)가 필요한데, 이걸 DRAM에서 매번 가져오면 에너지 대부분이 이동에 쓰입니다 → **Memory wall**, 그리고 정두석 교수님 CIM 연구의 출발점.

## 3. RTL 관점 — 오늘 만든 것 (1.5시간)

`rtl/mac.sv` 를 **한 줄씩 읽고 직접 설명할 수 있어야 합니다.** 핵심 포인트:

| 포인트 | 설명 |
|---|---|
| `logic signed` | INT8은 2의 보수. signed를 빼먹으면 -1이 255로 계산됨 |
| `prod` 폭 = 16bit | 8b×8b 곱은 최대 16bit. 가장 큰 값은 (-128)×(-128)=16384 |
| sign extension | 16bit 곱을 32bit 누산기에 더할 때 부호 비트를 복제해야 음수가 유지됨 |
| `ACC_W = 32` | N개 누적 시 필요 비트 = 16 + ⌈log₂N⌉. 32bit면 65,536개까지 overflow 없음 |
| `clr & en` | 새 dot product를 "0 로드 후 누적"이 아닌 "첫 항 로드"로 시작 → 1 cycle 절약 (systolic array에서 중요) |
| `always_ff` + 비동기 reset | 누산기 = 32개의 flip-flop |

**실행:**
```bash
make sim     # PASS (6036 checks) 가 나와야 함
make wave    # GTKWave에서 clk, en, clr, a, b, acc 관찰
```

파형에서 꼭 확인할 것: `acc`는 입력이 바뀐 **다음 클럭 엣지**에서 바뀐다 (레지스터 = 1 cycle latency).

## 4. 반도체 관점 — MAC은 합성하면 무엇이 되나 (30분)

```bash
make synth
```

IN_W=8일 때 generic gate 약 720개:
- **XOR/XNOR 많음** → 덧셈기(full adder = XOR 2개 + AND/OR)
- **AND/NAND 많음** → 곱셈기의 partial product (a_i AND b_j 가 64개)
- **DFF 32개** → 누산기 레지스터

정밀도별 비교 (이미 돌려본 결과):

| IN_W | Cells | 비율 |
|---|---|---|
| 4 | 384 | 0.53× |
| 8 | 719 | 1× |
| 16 | 2019 | 2.8× |

곱셈기는 대략 **비트수²** 로 커집니다 (누산기 32bit는 고정이라 비율이 정확히 4배는 아님). → INT8/INT4 quantization이 하드웨어에서 왜 중요한지의 첫 번째 증거. Week 4 실험의 예고편입니다.

## 5. 논문 연결 (정두석 교수님 방향) (10분)

> "MAC array는 연산은 싸지만, weight와 activation을 메모리에서 PE로 옮기는 비용이 더 크다. CIM은 아예 **메모리 배열 안에서 MAC을 수행**해 이동을 없앤다."

RRAM crossbar에서는 옴의 법칙(I = G·V)이 곱셈, 키르히호프 전류 법칙(전류 합)이 덧셈 → 아날로그 MAC. 이번 주 논문 읽을 때 이 관점으로 보면 됩니다.

---

## ✍️ 직접 해볼 과제 (중요 — 코드를 "받은 것"이 아니라 "만든 것"이 되도록)

1. **[필수]** `mac.sv`에서 `signed`를 모두 지우고 `make sim` → 어떤 테스트가 왜 실패하는지 설명해보기. 확인 후 원복.
2. **[필수]** `ACC_W`를 16으로 바꿔 시뮬레이션 → 1024×16384 테스트에서 무슨 일이 일어나는지 (overflow wrap) 확인.
3. **[추천]** Saturation 옵션 추가: `parameter bit SAT = 0` — overflow 시 wrap 대신 최대/최솟값으로 고정. 테스트 추가.
4. **[도전]** 곱셈 결과를 레지스터에 한 번 저장하는 **2-stage pipeline MAC** (`mac_pipe.sv`)을 만들고, latency가 1→2 cycle로 바뀌는 것을 테스트벤치로 검증. (Week 3에서 Fmax 비교에 사용)

## ✅ 오늘 체크리스트

- [ ] 로컬에 iverilog / verilator / yosys / gtkwave 설치 (`scripts/setup_mac.sh`)
- [ ] `make sim`, `make sim-vl` PASS 확인
- [ ] 파형에서 1-cycle latency 확인
- [ ] 과제 1, 2 완료
- [ ] GitHub에 `tiny-ai-accelerator` repo 생성 후 첫 push
- [ ] 이 노트의 1~5를 **안 보고** 5분 동안 말로 설명해보기 (면접 연습)

## 면접 대비 한 줄 답

**Q. MAC이 뭡니까? 왜 중요합니까?**
A. 곱셈-누산 연산으로, DNN의 행렬곱이 결국 MAC의 반복이기 때문에 AI 가속기의 기본 연산 단위입니다. 제가 직접 INT8 MAC을 설계해 합성해 보니 곱셈기 면적이 비트폭의 제곱에 가깝게 증가했고, 이것이 저정밀도 양자화가 하드웨어 효율에 직결되는 이유라는 걸 확인했습니다.
