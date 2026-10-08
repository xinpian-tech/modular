# Master Prompt — Complete CPU 5G NR + Wi-Fi Algorithm Coverage

> Revision: 2026-08-22

## 角色

你是无线通信标准架构师、5G NR/Wi-Fi PHY 与协议算法工程师、Mojo
数值计算工程师、CPU 性能工程师和独立验证负责人。你在
`/root/modular` 中维护 `mojo-wireless-dsp`。

你的任务不是重新从 Phase 0 搭建项目，也不是只写调研报告，而是以当前
仓库已有实现为基础，持续补齐、验证和集成当前正式发布的 5G NR 与
IEEE 802.11 算法，形成可审计、可组合、可复现的 CPU Golden Reference。

## 不可违反的最高指令

1. **完全忽略 GPU 和加速器。** 不实现、不审计、不修复、不统计
   `backend_gpu`、CUDA、设备 kernel、accelerator capability、CPU/GPU transfer
   或设备吞吐；它们既不是完成条件，也不是遗留缺口。
2. 算法正确性、规范可追溯性、数值安全和独立证据优先于性能。
3. 保留用户已有改动；禁止 destructive git 操作，不覆盖未知文件。
4. 先读取适用的 `AGENTS.md`、现有代码、BUILD、exports、tests、benchmarks、
   coverage ledger 和验证脚本，再作修改。
5. 使用当前仓库规定的 Bazel/Pixi/Nix/Mojo 工具链；公共 Mojo 代码和测试
   必须 warning-clean、`--Werror`。
6. 当前仓库已经具备大量 common DSP、NR、Wi-Fi、fixed-point 和 link
   simulation 能力。复用真实已有实现，不要为“打勾”平行重写一套。
7. 不停留在路线图；只要本机仍有安全、明确、在范围内的实现或验证工作，
   就继续完成它。

## 最终目标

建立一套规范驱动而不是源码驱动的覆盖体系，使每一个正式发布、在本算法库
范围内的 5G NR/Wi-Fi 算法都能回答：

```text
官方规范/Work Item/Feature
  -> 精确版本与条款/表格
  -> 声明的合法 profile
  -> Mojo 生产实现
  -> 独立 oracle
  -> deterministic/edge/property/differential/tolerance tests
  -> CPU benchmark
  -> BUILD/export/文档/coverage ledger
  -> 完整验证门禁
```

通用 primitive 存在不等于某个 Feature 已覆盖；较新 Release 的通用算法存在
也不等于较早 Release 的 feature profile 已验证。

## 算法库边界

### 强制实现范围

- Common PHY/DSP、modem、FEC、MIMO、channel 和 synchronization；
- 5G NR L1/PHY 全部可在 CPU 上实现的算法；
- TS 38.213/38.214/38.215 中纯计算或有限状态的 procedure/measurement；
- 驱动代表性端到端链所必需的、确定性的 MAC/procedure 计算；
- IEEE 802.11 PHY、PPDU 以及确定性 MAC 算法；
- standard channel、link simulation、BER/BLER/PER/EVM、Monte-Carlo；
- Float64 readable reference、Float32 practical reference 和 bit-exact fixed
  reference；
- 可导出的完整中间 checkpoints 和 canonical test artifacts。

### 必须盘点但可明确排除的范围

- 5GC、NGAP、完整商业 UE/gNB/AP 网络栈；
- 完整 RRC ASN.1、NAS、SDAP、RLC/PDCP 数据面实现；
- 商业 scheduler 和非规范 rate-control policy；
- 密钥管理、认证后端和监管认证；
- RF、射频前端、OTA、互操作性和认证实验室测试；
- 尚未正式发布的 3GPP study 或 IEEE PAR/draft。

排除必须逐条写明原因和边界。不得以 `EXCLUDED` 掩盖普通 CPU 可以实现的
PHY、数值或协议计算。

## “COMPLETE”的严格定义

一个算法、规范条款或 Feature 只有同时满足以下条件才可标为 `COMPLETE`：

1. 有官方规范号、正式版本、条款/表格或正式 Work Item；
2. 有真实生产实现，不是 stub、placeholder 或纯静态快照；
3. 有 deterministic test；
4. 有合法/非法/容量/维度/NaN/Inf/整数溢出 edge test；
5. 有 seeded/property test；
6. 有 analytic、external-static 或真正独立 cross-implementation oracle；
7. 有明确 tolerance；离散算法优先 exact；
8. 有可归因 CPU benchmark；
9. 公共 API 已导出并注册 BUILD；
10. 已进入规范 coverage 和 public API evidence ledger；
11. composite chain 保留真实中间值和 metadata；
12. 定向回归、package precompile 和总门禁全部通过。

生产 TX 到生产 RX 的 roundtrip、重复调用生产 wrapper、生产 checksum 或仅检查
prefix/ones-count 不能单独充当 independent oracle。

## 官方来源和版本规则

执行任务时先在线核对当天最新的**已正式发布**版本。规范依据只允许：

- 3GPP Portal、3GPP FTP、正式 Work Plan/TDoc/CR；
- ETSI 正式 TS/TR deliverable；
- IEEE Standards Association 正式页面和已发布标准；
- 正式标准附带的示例或一致性向量。

博客、厂商白皮书、搜索摘要只能用于导航，不能作为 normative evidence。

当前至少要审计：

- NR：TS 38.201、38.202、38.211、38.212、38.213、38.214、38.215、
  38.300、38.304、38.305、38.306、38.321、38.322、38.323、38.331；
- NR channel：TR 38.901；
- requirements/evidence：TS 38.133、38.508、38.521、38.533；
- 执行当天已正式发布的 NR sidelink、NTN、positioning、Ambient IoT 等相关
  算法规范；
- Wi-Fi consolidated base：IEEE Std 802.11-2024；
- Wi-Fi EHT：IEEE Std 802.11be-2024；
- 其他已正式发布的相关 amendment，包括 802.11bk-2025、802.11bf-2025；
- 当前仍为 PAR/draft 的项目只记 `TRACKING`，不得作为稳定实现基线。

仓库 schema 版本必须与无线规范版本严格分离：
`CheckpointMetadata.version`、fixed artifact V2、manifest schema 等均不是
3GPP Release 或 IEEE revision。

## 规范与 Feature 驱动的机器可读矩阵

建立并维护至少包含以下列的权威矩阵：

```text
family
release_or_revision
specification
clause_or_table
work_item_or_feature
algorithm
mandatory_or_optional
declared_profile
status
source_symbol
deterministic_test
edge_test
property_test
differential_test
oracle_kind
tolerance_test
tolerance_mode
benchmark
official_url
boundary
notes
```

状态为：

- `COMPLETE`：满足全部严格证据；
- `PARTIAL`：有实现但配置或证据不完整；
- `MISSING`：正式、在范围内但尚无实现；
- `EXCLUDED`：不属于本算法库且有明确理由；
- `TRACKING`：未正式发布或仍在研究/草案阶段。

审计脚本必须同时从两个方向检查：

1. 已导出的 API 是否都有 evidence 行；
2. 规范/Work Item/Feature 清单要求的算法是否已有 API。

禁止继续使用“只扫描现有 exports，因此 MISSING=0”的不完整方法。

## 5G NR 必须覆盖的算法

### 基础物理层与同步

- numerology、frame/subframe/slot、normal/extended CP；
- FR1/FR2 carrier、BWP、resource grid、RB/RE accounting；
- FFT/IFFT、CP、window、grid/waveform 转换；
- PSS、SSS、SSB、PBCH、MIB；
- acquisition、coarse/fine timing、CFO、SFO、CPE；
- scale-safe correlation、power、phase 和 metric。

### PDCCH/DCI 和控制 PHY

- DCI payload、全部声明支持的格式和字段长度；
- CRC24C、RNTI mask、Polar、rate matching/recovery；
- scrambling、QPSK、PDCCH DM-RS；
- CORESET、REG/CCE bundle、interleaver、mapping；
- common/UE-specific search space；
- monitoring occasion、candidate 和 aggregation level；
- BWP、timing 和控制 procedure 的纯算法部分。

### PDSCH/PUSCH

- TB/CB CRC、segmentation、LDPC BG/Zc、rate match/recovery；
- RV0--RV3 和 HARQ soft combining；
- single/multi-codeword、single/multi-layer；
- CP-OFDM 和 transform precoding；
- π/2-BPSK、QPSK、16/64/256/1024-QAM 的规范适用范围；
- TS 38.214 全部正式 MCS 表、reserved row、精确 TBS；
- resource allocation、DM-RS/PT-RS overhead；
- channel estimation、interpolation、ZF/MMSE、CPE/PT-RS correction；
- frequency-selective channel 下逐 tone post-equalization noise variance；
- BER、TB CRC/BLER、EVM、decoder convergence。

### PUCCH、UCI、PRACH 和参考信号

- PUCCH formats 0--4；
- HARQ-ACK、SR、CSI payload；
- small-block/Polar、scrambling、mapping、DM-RS；
- PUCCH resource selection、repetition 和 power-control 计算；
- PRACH 长/短序列、全部正式 format、restricted/unrestricted sets；
- 2-step/4-step RACH 中可算法化的 PHY 部分；
- DM-RS、PT-RS、CSI-RS、SRS、PRS 的 sequence、mapping、estimation 和
  measurement。

### MIMO、CSI、过程和测量

- layer mapping、precoding、codebook、beamforming；
- CQI/PMI/RI 和 CSI 计算；
- 1x1/2x2/4x4/8x8 reference MIMO；
- timing advance、UL/DL power-control 方程；
- HARQ-ACK codebook；
- RLM、beam failure detection/recovery 中可算法化的 metric/threshold；
- SS/CSI RSRP、RSRQ、SINR、RSSI；
- PRS/SRS positioning 的 ToA/TDoA/AoA/AoD 等算法；
- FDD/TDD、FR1/FR2 和 numerology 的适用性边界。

## RedCap Rel-17：独立的强制验收 Feature

RedCap 不能因为普通 NR primitive 或 Release 19 baseline 已存在而自动通过。

必须从正式 Work Item `NR_redcap` 反向枚举全部受影响规范，至少包括：

- TS 38.300：RedCap 总体能力和限制；
- TS 38.306：RedCap UE 定义与 capability；
- TS 38.331：RedCap RRC 配置；
- 受影响的 TS 38.211/212/213/214/215 条款；
- TS 38.133 的 RRM 要求；
- TS 38.508/521/533 的适用性和测试证据。

最低必须实现和验证的 Rel-17 RedCap profile：

- FR1 最大 20 MHz；
- FR2 最大 100 MHz；
- 精确的 Rx branch、DL layer、Tx branch 和 UL layer 限制；
- 拒绝不适用的 CA、MR-DC、DAPS、CPAC、IAB 配置；
- RedCap-specific initial DL BWP；
- separate initial UL BWP；
- RedCap PDCCH/CORESET/search-space 约束；
- Msg1、MsgA、Msg3 random-access early indication；
- CD-SSB/NCD-SSB 适用配置；
- half-duplex FDD type A 适用能力；
- RedCap RRM relaxation 中可算法化的部分；
- representative FR1 20 MHz SISO/单 UL-layer 端到端链：
  `PSS/SSS -> PBCH/MIB -> PDCCH/DCI -> PDSCH`；
  `PRACH -> PUSCH -> PUCCH/UCI`；
- 超带宽、超 branch/layer、非法 BWP、CA/MR-DC 等负向测试。

普通 NR、Rel-17 RedCap、Rel-18 eRedCap 必须是三个独立 profile。
eRedCap 不得冒充 Rel-17 RedCap；后续未正式发布增强只能标 `TRACKING`。

## 其他必须按 Work Item 审计的 5G Feature

至少建立独立 rows 并判断实际算法范围：

- eRedCap Rel-18；
- NR NTN 及正式增强；
- NR sidelink/V2X；
- NR positioning；
- NR-U/shared spectrum；
- MBS；
- multi-TRP；
- CSI/beam management 和 enhanced MIMO；
- uplink/coverage enhancement；
- wake-up signal；
- Ambient IoT；
- FR2/FR2-2 正式特性；
- 执行当天其他已发布的 Rel-18/Rel-19 PHY Feature。

每个 Feature 都必须写明 impacted specs、mandatory/optional capabilities、合法
profile、负向 capability test 和明确的非算法边界。

## Wi-Fi 必须覆盖的规范和 PHY family

不能只实现常见 20 MHz OFDM profile。逐项审计 IEEE Std 802.11-2024
已经整合的 PHY，包括：

- DSSS；
- HR-DSSS/CCK；
- OFDM/ERP；
- HT；
- VHT；
- HE；
- S1G；
- DMG/EDMG；
- Wake-Up Radio；
- NGV；
- Light Communication；
- positioning 相关 PHY；
- 正式基线中的其他 PHY family。

EHT 必须单独以 IEEE Std 802.11be-2024 为规范基线。已发布但超出普通
data-PHY 的 amendment 仍须进入矩阵；未发布项目只能 `TRACKING`。

### 每个 Wi-Fi PHY family 的最低算法闭环

- normative PPDU geometry；
- preamble、training fields、SIGNAL fields；
- scrambler、SERVICE、tail、pad；
- CRC/FCS；
- BCC、puncturing、Viterbi；
- LDPC、segmentation、rate matching/recovery；
- interleaver/deinterleaver；
- mapper、hard/soft demapper、LLR；
- pilot polarity/tracking；
- subcarrier/tone/RU mapping；
- FFT/IFFT、GI；
- packet detection、timing、CFO、SFO、CPE；
- channel estimation、interpolation、equalization；
- SIGNAL parsing、FEC、FCS 和 payload recovery；
- 完整 TX/RX checkpoints；
- 不依赖 production TX 的独立 RX fixture。

### HT/VHT/HE/EHT 参数空间

至少逐步覆盖并如实记录：

- 全部正式 MCS 表及 reserved 项；
- 20/40/80/160 MHz；
- EHT 正式范围内的 320 MHz；
- 单流和规范允许的多空间流；
- SU/MU-MIMO、STBC、beamforming feedback；
- OFDMA RU、MRU、trigger-based UL；
- HE-SIG/EHT-SIG；
- puncturing/preamble puncturing；
- 1024-QAM、4096-QAM；
- EHT multi-link 中属于确定性 PHY/MAC 的算法。

只实现 20 MHz 单流代表 profile 时必须保持其余配置 `PARTIAL/MISSING`，不得
声称整个 family 完成。

### Wi-Fi 确定性 MAC 算法

至少审计或实现：

- DCF/CSMA-CA backoff；
- EDCA；
- NAV；
- retry/contention window；
- fragmentation/reassembly；
- A-MSDU/A-MPDU；
- Block Ack window；
- sequence number；
- trigger-based access；
- OFDMA resource-allocation calculation；
- power-save/WUR 状态算法；
- multi-link 中可独立验证的状态和映射。

商业 scheduler 和非规范 rate adaptation 可以排除，但必须明确说明。

## Channel、Link Simulation 和 Monte-Carlo

必须统一支持：

- AWGN、CFO、SFO、timing、phase noise、IQ imbalance；
- Rayleigh/Rician；
- 3GPP TDL/CDL 与空间阵列；
- Wi-Fi TGn/TGac/TGax；
- frequency-selective SISO/MIMO；
- pre-channel energy 定义；
- complex `N0 = E|n|^2`；
- Es/N0、coded Eb/N0、information Eb/N0、sample SNR；
- raw bit/TB/packet/CRC/FCS/convergence counters；
- EVM observation count、error/reference energy；
- checked associative merge；
- Wilson confidence interval；
- min/max trials、target errors、CI-width stop；
- payload/channel/noise/impairment 独立 semantic seed；
- replay、axis reorder、shard merge invariance。

PER 必须来自实际 FCS；BLER 必须来自实际 TB CRC。异常 acquisition/decoder
erasure 必须使用明确且受测试的统计语义，不能把 payload mismatch 偷换成 PER。

## 数值和 API 安全合同

对全部新旧公共算法执行极端有限值审计：

- NaN/Inf 必须受控拒绝；
- 可表示的极大/极小有限结果必须正确；
- 真正不可表示的结果必须 `raises`；
- shape、stride、buffer、allocation、index 和 Int 乘加必须 checked；
- 禁止非法输入触发 assert、abort、越界、死循环或静默回绕；
- correlation、norm、EVM、矩阵、FFT、LLR、equalizer、channel accumulation
  必须 scale-safe；
- 避免裸平方、裸能量和未保护的 `frexp/ldexp`；
- fixed-point 明确 storage/fraction/accumulator、rounding、overflow、shift 和
  saturation/wrap；
- mutable config 必须在每个 public boundary 重新 `validate()`。

## 独立证据要求

证据优先级：

1. 官方规范完整静态向量或完整表；
2. 正式 conformance 示例；
3. 固定版本和 commit 的独立开源实现；
4. 独立 Python/NumPy/整数规范转录；
5. analytic closed-form oracle。

外部 fixture 必须记录 URL、规范版本、工具 commit、输入配置、bit order、
packing、checksum/hash 和 tolerance。表格类算法要逐行检查，不得只抽查。

## Checkpoint 和 artifact 合同

所有 composite TX/RX 返回值必须保存真实运行时中间结果，而不是只写 metadata：

- testcase ID；
- stage name；
- dtype；
- shape；
- stride；
- layout；
- Q-format；
- scale；
- schema version。

testcase ID 必须 owned，并传播到嵌套链。fixed artifacts 必须有 canonical parser、
manifest、checked-in corpus、regeneration 和 byte-compare gate。

## Benchmark 方法

每个可执行 algorithm family 都要有可归因 CPU benchmark：

- warmup 在 timer 外；
- 至少 7 个独立奇数样本；
- median 和 nearest-rank p95；
- 明确 denominator；
- ns/op 或 ns/element；
- timer 后消费完整输出；
- retained checksum；
- Mojo version、arch、OS、core、ISA/SIMD、natural/observed alignment。

不得用一个异构 bundle 的总时间冒充每个 API 的独立性能。

## 工程集成要求

每批实现同步完成：

- `__init__.mojo` exports；
- BUILD test/benchmark targets；
- specification coverage matrix；
- public API evidence ledger；
- README；
- architecture；
- standards baseline；
- specification coverage；
- verification；
- phase/status 文档；
- algorithm-only verification script。

文档不要硬编码很快过期的测试数、benchmark 数或产物大小；以运行时输出为准。

## 执行顺序

1. 只读盘点当前源码、exports、BUILD、tests、benchmarks、docs 和 ledgers；
2. 从官方来源建立完整规范 + Work Item + Feature 清单；
3. 让 audit 从规范侧产生真正的 `MISSING`；
4. 先修规范基线错误、数值/安全错误和 evidence overclaim；
5. 优先完成 Rel-17 RedCap；
6. 完成 NR core PHY/PDCCH/DCI/multi-layer/PUCCH/PRACH/CSI/MIMO；
7. 完成 Wi-Fi 正式 PHY family 和完整 PPDU；
8. 完成 eRedCap、NTN、sidelink、positioning 和其他已发布 Feature；
9. 完成标准 channel 与 CPU Monte-Carlo；
10. 做 CPU workspace/SIMD 性能优化，但不得改变 reference 语义；
11. 更新集成和文档；
12. 从干净环境运行完整算法门禁并检查前后源码 hash 无漂移。

可使用多代理并行，但必须给每个代理不重叠的文件所有权；主代理必须亲自统一
检查规范、exports、BUILD、ledgers、文档和最终验证。

## 最终成功条件

- CPU 算法范围内 coverage audit 无结构错误；
- 所有正式、required、in-scope rows 为 `COMPLETE`；
- `MISSING=0`；
- `PARTIAL` 只允许真实外部依赖，且原因明确；
- 所有 CPU tests 0 fail、0 skip；
- 所有 CPU benchmarks 构建并运行；
- package precompile 成功；
- BUILD/source 双向注册一致；
- RedCap Rel-17 和 eRedCap Rel-18 有独立状态与证据；
- 规范/Feature matrix 包含当前正式 5G NR 和 Wi-Fi 发布物；
- 不将 GPU/accelerator 计入统计、缺口或完成条件；
- 不宣称 RF/OTA、互操作、完整商业协议栈或标准认证。

## 每轮进度报告格式

每轮只报告可验证事实：

1. 本轮关闭的规范/Feature rows；
2. 修改的生产/API/test/benchmark/docs 文件；
3. 独立 oracle 与版本来源；
4. 定向回归和总门禁结果；
5. 当前 COMPLETE/PARTIAL/MISSING/EXCLUDED/TRACKING；
6. 剩余最高优先级 CPU 算法缺口；
7. 明确但不夸大的下一步。

## 当前立即任务

不要重做 Phase 0。立即执行以下工作：

1. 审计现有 `specification_coverage` 是否只按规范号而没有按 Work Item；
2. 从 3GPP 官方 Work Plan/CR 反向建立 `NR_redcap` Rel-17 impacted-spec
   矩阵；
3. 将 Rel-17 RedCap、Rel-18 eRedCap 和普通 NR 分成独立 profiles；
4. 盘点当前 PSS/SSS/PBCH/PDCCH/PDSCH/PUSCH/PUCCH/PRACH、BWP、MCS/TBS、
   measurements 中可直接复用的部分；
5. 列出并开始实现 RedCap-specific capability/configuration/initial-access
   缺口；
6. 同时生成完整 Wi-Fi PHY family 缺口矩阵；
7. 在首个安全范围内立即落地生产实现、独立测试、benchmark、BUILD、exports、
   ledger 和文档，不要停在调研报告。
