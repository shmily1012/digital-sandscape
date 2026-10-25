# Historical commands and experiments

历史说明归档；当前启动方式与已知缺陷以根目录README为准。

## 保存并继续当前作品

双击 `Digital Sandscape.cmd`，或运行 `python run.py sandscape`。
鼠标拖动旋转，空格暂停，Ctrl+S保存；每120秒和正常退出也会保存，下次启动继续上次作品。
新模型存档与旧app独立。已有存档时恢复其中的种子、尺寸和物理参数；若只想查看新种子而不覆盖作品，使用 `python run.py sandscape --fresh-session --seed=123`。

存档自动验证：`python run.py sandscape-session`。物理仍属实验阶段，整层承载和自然沙诱导分裂未验收。

## 当前多气泡作品预览

双击 `Sandscape Preview.cmd`，或运行 `python run.py sandscape-preview`。
鼠标拖动旋转，空格暂停。不同大小的气泡与黑白灰沙实时演化；当前已观察到气泡合并、泡间漏沙与沉积，旋转保留状态。
这是临时物理预览，退出不保存。整层承载与自然沙诱导分裂仍未验收；默认 `app` 仍为旧基线。

自动窗口验证：`python run.py sandscape-preview-smoke`。

## 单泡承载诊断入口

双击根目录 `Bubble Demo.cmd`，或运行 `python run.py bubble-demo`。
鼠标拖动旋转，空格暂停。实时 GPU 气液与沙粒演化使用现有单粒能量交换候选；旋转保留当前状态。
当前可观察上方留沙、两侧漏沙与底部堆积。沙层接触载荷和自然沙诱导分裂尚未验收；本入口不会保存或覆盖作品存档，退出后不恢复。
默认 `app` 仍是旧基线。此入口用于直接观察当前候选，不表示气泡物理已完成。

自动窗口检查：`python run.py bubble-demo-smoke`。
多角度与独立重放：`python run.py phase-cycle --contact-bed --energy-exchange --wetting-cosine=0.5`。

> 当前主应用已接入守恒气体/液体交换的格点近似。运行 `python run.py app`，鼠标拖动圆框或滑块旋转，空格暂停，V 在细沙/直接颜色视图间切换。气泡释放、堆积与艺术效果尚未完成验收；当前恢复计划见 [docs/DELIVERY_PLAN.md](docs/DELIVERY_PLAN.md)。独立高成本求解器不在主应用运行路径上。

# Digital Sandscape

分区GPU压力验证：`python run.py cut-cell-gpu`。检查冻结拓扑上的压力/惯性算子、有界迭代、分区源项相容性、真实残差、压力/反力共同发布与失败恢复，以及收敛后跳过计算。同格断开的液体区域保持分离。尚不运行完整气泡或更新主窗口；报告见 `reports/cut-cell-operator-gpu.json`。

更严格精度诊断：`python run.py cut-cell-precision`，固定256槽位比较10⁻⁷/10⁻⁸/10⁻⁹，并以CPU从候选压力独立重算原方程。报告分别列出达到精度的数量和安全拒绝；命令退出0不表示所有目标精度均已达到。

当前可交互的联合物理诊断窗口：双击 `Open Coupled Lab.cmd`，或运行：

```powershell
python run.py coupled-lab
```

拖动圆形画面或滑块旋转，点击 Pause / Resume 暂停。窗口直接显示共同发布的 GPU 颗粒状态；这是放大的两粒诊断模型，有平面支撑、封闭载液和圆形颗粒边界，尚无气泡/浓沙模型，不是最终流沙画视觉。默认 `python run.py` 仍启动旧网格基线，不能据此判断新联合物理已经产品化。

当前证据与限制以 [阶段报告](reports/PHASE_REPORT.md) 和 [耦合模型](docs/COUPLED_CONTACT_MODEL.md) 为准。窗口自动检查：`python run.py coupled-smoke`。下列早期实验记录保留研究路径，其中旧状态描述不代表当前完成度。


历史实验记录：[快速自响应核候选](reports/FAST_SELF_KERNEL.md)。1296 字节核、128 次 GPU 查询约 0.31–0.56 ms；12 个内部点的速度近似误差约 0.07%–0.56%。仍未接入粒子演化或完整耗散检查。

颗粒校准批次检查：`python run.py batched-grains`。温启动约 21 ms/步，但冷启动/反转仍约 52–69 ms；物理状态与精确基准一致，仍不满足产品预算。见 [在线校准报告](reports/ONLINE_GRAIN_CALIBRATION.md)。

历史实验记录：[GPU 当前位置颗粒校准](reports/ONLINE_GRAIN_CALIBRATION.md)。8 步移动与反向重力对照通过，无中途粒子场读回；但三颗粒已需约 47–52 ms GPU/步，仅保留为参考，未接入默认窗口。

历史实验记录：颗粒自响应参考修正通过 16²/32²/64² 单颗粒检查，76 项 CPU 与六组 GPU 单步对照通过；GPU 矩阵仍由 CPU 在初始位置校准，实时移动校准未实现。见 [颗粒报告最新部分](reports/GRAIN_CARRIER_COUPLING.md)。

历史实验记录：[颗粒/载液耦合候选](reports/GRAIN_CARRIER_COUPLING.md)。实现对照通过，但单颗粒检查发现自身扰动回采样造成网格依赖，物理尚未验收，未接入主窗口。

历史实验记录：压力与条件输运已合并，主设备完成延迟回到约 66 ms，局部 GPU p50 约 1.01 ms；新增 `python run.py lab-rejection` 验证预算失败后状态保留与恢复。见 [预算报告最新部分](reports/COUPLED_GPU_BUDGET.md)。

历史实验记录：[两相 GPU 预算实测](reports/COUPLED_GPU_BUDGET.md)。`python run.py coupled-benchmark` 比较压力批大小；小批量降低局部 GPU 成本，但主设备完成延迟升至约 133 ms，仍需优化异步轮次。

历史实验记录：[主设备实时两相实验](reports/LIVE_TWO_PHASE_LAB.md)。`python run.py live-lab` 打开实验窗口，`python run.py lab-smoke` 自动验证；200 步与在途关闭通过。当前只有气/液两相，32² 低分辨率，尚无沙粒或产品视觉。

历史实验记录：有界邻域备用曲率使 **200 步毛细反馈通过**，69 项 CPU 测试及七组曲率 GPU 对照通过。见 [曲率报告最新部分](reports/GPU_CAPILLARY_FEEDBACK.md)；仍不是完整颗粒/气泡流沙画或长稳验收。

毛细反馈更新：近纯相分类修复使 40 步通过；延长至 200 步后，第 159 步仍触发不可解析保护。当前未完成持续毛细物理验收，见 [诊断报告](reports/GPU_CAPILLARY_FEEDBACK.md)。

历史实验记录：[GPU 曲率与毛细反馈诊断](reports/GPU_CAPILLARY_FEEDBACK.md)。静态曲率对照通过；`python run.py capillary-feedback` 的持续演化目前失败，已定位高度函数对近纯相非单调误差的敏感性，尚未解决。

历史实验记录：[气相状态驱动的 GPU 浮力反馈](reports/BUOYANCY_FEEDBACK.md)。`python experiments/liquid/buoyancy_fixtures.py` 后运行 `python run.py buoyancy`，验证当前界面→浮力→压力→界面的 40 步演化与重力反转。尚无表面张力或沙粒接触。

持续状态检查：`python run.py continuous-transport`，同一组 GPU 缓冲经历正向/非法输入拒绝/反向共 41 步；详情见 [压力输运报告](reports/PRESSURE_TRANSPORT.md)。仍是外部驱动力实验，尚无界面到压力的反馈。

历史实验记录：[GPU 压力到界面输运](reports/PRESSURE_TRANSPORT.md)。运行 `python experiments/liquid/pressure_transport_fixtures.py` 后 `python run.py pressure-transport`；六组检查通过，动态 CFL 和失败保留已验证，仍未接入主应用或颗粒接触。

历史实验记录：[GPU 几何界面输运](reports/GPU_GEOMETRIC_TRANSPORT.md)。运行 `python experiments/liquid/geometric_fixtures.py` 后 `python run.py geometric`；五组多步 CPU/GPU 对照通过，动态压力/沙粒耦合尚未接入。

历史实验记录：[主设备异步压力任务](reports/ASYNC_PRESSURE.md)，运行 `python run.py async-pressure`。主设备、16 字节异步状态、有界在途队列与压力发布门控已实机验证，完整物理 tick 尚未接入。

历史实验记录：[GPU 残差控制与温启动](reports/ADAPTIVE_PRESSURE.md)，运行 `python run.py adaptive`。实机验证未收敛/非法输入拒绝及压力持续复用；预排命令开销仍高，尚未接入产品。

历史实验记录：[多层 GPU 压力求解](reports/MULTIGRID_PRESSURE.md)。先运行 `python experiments/liquid/multigrid_fixtures.py`，再运行 `python run.py multigrid`。六组实机对照通过；减少压力工作量，仍未达到产品预算或接入主应用。

历史实验记录：[几何界面与毛细动态耦合](reports/SURFACE_EVOLUTION.md)。运行 `python experiments/liquid/surface_validation.py` 验证两相界面的短时连续演化；仍为 CPU 实验，尚无沙粒耦合或产品接入。

历史实验记录：[毛细力与压力平衡](reports/CAPILLARY_BALANCE.md)。运行 `python experiments/liquid/capillary_validation.py` 检查圆泡压差及伪流。局部曲率估计仍有尺寸/边界限制，尚未接入演化与主程序。

历史实验记录：[保守界面输运改进](reports/INTERFACE_TRANSPORT.md)，新增 CPU 限幅线性重建与 RK2；运行 `python experiments/liquid/run_experiment.py --scheme muscl`。减少数值扩散，尚无表面张力或产品接入。

新增 [液体压力与回流实验](reports/LIQUID_RETURNFLOW.md)：`python experiments/liquid/fixtures.py` 后运行 `python run.py liquid`；`python experiments/liquid/run_experiment.py` 验证旋转中的五材料保守输运。压力/通量已做 GPU 对照，输运目前为 CPU，界面扩散尚待解决。

新增 [E2 功能气泡候选实验](reports/EXPERIMENT_E2.md)：`python experiments/bubbles/fixtures.py` 后运行 `python run.py bubbles` 做真实 GPU 对照；`python experiments/bubbles/run_experiment.py` 生成释放曲线。它尚未接入应用，也不代表三相物理已验收。

*A living piece of art for your desktop.*

**物理重审中**：当前程序是 GPU 工程基线，尚不是可信的液体流沙画模型。厂家依据、代码缺陷、三个实验及本轮诊断见 [物理重审](docs/PHYSICS_REASSESSMENT.md)。运行诊断：`python tests/physics_reassessment.py`。

新的独立 [E1/E3 实验](reports/EXPERIMENTS_E1_E3.md) 已实现，未替换主程序：`python experiments/settling/fixtures.py` 后运行 `python run.py settling` 验证真实 GPU 沉降；`python experiments/deposition/run_experiment.py` 运行有限库存接触床实验。整体未完成事项见 [TASK_STATUS.md](TASK_STATUS.md)。

Godot 4 GPU 流沙画的 M1 工程原型：密封圆形、三类单色沙、鼠标旋转、连续物理状态。已在 **Godot 4.7.2 / Windows / RX 7900 XTX / Vulkan Mobile** 运行，GPU 差分、守恒与主窗口自动化测试通过。视觉仍偏粗，尚未达到真实液体流沙画的山脉与气泡效果。详见 [最新验证报告](reports/RUNTIME_VALIDATION.md)。无预录视频或预生成山脉。

## 启动
用户提供的 Godot 便携版已解压至 `.tools/godot-4.7.2/`。在本目录运行：

```powershell
python run.py
```

鼠标拖动圆内或底部滑块旋转；Space 暂停/恢复。默认 256²；可用 `python run.py --size=512 --seed=20261024`。失焦后以 5 Hz 缓慢演化，关闭会结束本次会话，尚无磁盘恢复。

启动器仅为子进程设置项目内缓存路径，不改系统环境、驱动或 PowerShell 执行策略。亦可用便携 Godot 打开 `project.godot` 后 F5；不需要 Python 第三方库、.NET 或全局安装。原规划 4.6.1 未实测，当前验证基线是用户提供的 4.7.2。

## 测试
颗粒接触实验（独立于主窗口）：运行 `python experiments/deposition/gpu_fixtures.py` 后运行 `python run.py contacts`，比较真实 GPU 的持续状态和接触反力。当前是小接触组串行参考，性能不适合产品规模；见 [接触报告](reports/PARTICLE_CONTACTS.md)。

```powershell
python tests/run_validation.py
python run.py import
python run.py scheduler
python run.py gpu
python run.py smoke --size=256
python run.py smoke --size=512
python run.py benchmark
```

CPU 测试生成 GPU fixture；GPU 测试使用真实 Vulkan 后端，不可加 `--headless`。它验证 70 tick 的 CPU/GPU 字节一致性，并扩展到 1,000 tick 的旋转守恒检查。主窗口测试验证鼠标旋转、暂停时姿态与缩放不改变状态、翻转后的演化、材料守恒和退出释放，保存实际窗口截图。测试读回是验证专用路径，正常应用不逐帧读回。

GPU 基准是 local RD 一次物理 tick + colorize 的 60 个 GPU timestamp 样本（10 帧预热），排除 Canvas 绘制和运行时内存；不能作为完整应用利用率或长稳结论。

本受限环境仍打印 root certificate store 读取错误；离线模拟与测试成功，未修改系统证书或网络设置。macOS 未测试。

## 文档
- [产品规格](docs/PRODUCT_SPEC.md) / [架构](docs/ARCHITECTURE.md)
- [物理模型](docs/PHYSICS_MODEL.md) / [性能策略](docs/PERFORMANCE_STRATEGY.md)
- [路线图](docs/ROADMAP.md) / [参考研究](docs/RESEARCH.md)
- [风险](docs/RISKS.md) / [技术决策](docs/DECISIONS.md)
- [初始阶段报告](reports/PHASE_REPORT.md) / [本次实机验证](reports/RUNTIME_VALIDATION.md)

## 已知局限
颗粒和矿物层次仍粗糙；当前堆积轮廓常呈低谷/盆形，不能称为自然山脉效果已达标。液体只有简化阻力概率，无功能气泡、压力场和完整安息角模型。任意角度可输入，但 CPU 诊断仍有最高约 11.4° 的网格方向偏差。GPU 百分比预算、自动翻转、存档、壁纸和屏保均属后续里程碑。


## 独立颗粒接触实验

这是主应用之外的 16 粒局部阻力实验，尚无液体回流/气泡耦合，不代表流沙画已完成。

```powershell
python experiments/deposition/cycle_fixtures.py
python run.py refined-cycle
python experiments/deposition/refined_cycle_verify.py
```

最后一条命令独立检查完整 GPU 轨迹的接触力、边界、身份和逐步 CPU 位置对照。详见 [接触实验报告](reports/PARTICLE_CONTACTS.md)。


主渲染设备异步接触检查（先生成上面同步周期的对照文件）：

```powershell
python run.py async-contacts
```

验证每包 16 字节状态回调、240 步持续状态、预算拒绝、取消和在途关闭。它尚未替换主窗口的旧网格沙粒模型。


### GPU 接触历史局部核检查

先运行 `python experiments/deposition/tangential_history_fixtures.py`，再运行 `python run.py spring-history`。检查持久切向弹簧/滑移、CPU 对照与整批失败保留。此模式是规定滑移和载荷的局部核测试，不是可交互流沙应用；结果见 `reports/tangential-history-gpu.json`。


### GPU 圆盘几何算子检查

运行 `python experiments/deposition/geometric_operator_fixtures.py` 后运行 `python run.py geometric-operator`，检查几何面通量、反向力与拒绝发布。此测试中压力液流由 CPU 参考提供，尚非完整 GPU 排液链。结果见 `reports/geometric-operator-gpu.json`。

### GPU 排液算子实验

运行 `python experiments/deposition/drainage_gpu_fixtures.py` 后执行 `python run.py drainage-chain`。验证 GPU 固相通量→封闭压力→液流→阻力，含预算耗尽拒绝；不是主应用或完整颗粒演化。结果见 `reports/drainage-chain-gpu.json`。

压力优化验证：`python run.py drainage-chain` 执行三路径各三次对照；`python run.py adaptive-fused` 检查融合粗层后的压力复用、RHS 改变和拒绝行为。

可复用排液组件验证：`python run.py drainage-reuse`，检查持续复用、反转拒绝后恢复、NaN 后恢复及连续记录。组件位于 `experiments/deposition/drainage_operator_gpu.gd`，仍是实验接口。

GPU 外力求自由速度实验：依次运行 `python experiments/deposition/resistance_solve_fixtures.py`、`python run.py resistance-solve`、`python experiments/deposition/resistance_solve_check.py`。最后一步独立重算力平衡；尚无接触约束或位置演化。

### 会话连续性

主应用启动时恢复最近有效会话；Ctrl+S 手动保存，每 120 秒保存一次，正常关闭时再保存。内容包括全部沙/气体/液体单元、算法版本、种子、tick、角度、暂停与细沙样式。存储在 Godot `user://sessions`，两个轮换 JSON 槽并带 SHA-256 校验；最新槽损坏时回退上一份。两份均无效时保留文件并禁用该次自动保存，窗口显示提示。

`python run.py app --fresh-session` 打开不读写原存档的临时画面；此时 `--seed` / `--size` 用于新初始化。正常恢复优先采用存档中的 seed/size。本地启动器只在子进程中把用户数据目录放到 `.tools/runtime`，不修改系统环境变量。

验证：`python run.py session` 在专用测试目录执行 GPU 连续性、损坏回退、真实主窗口启动/手动/定时/关闭保存。保存时允许一次完整 GPU 读回，正常渲染不读回。两槽设计不保证断电时磁盘写入持久性；未测试 macOS 文件系统和所有分辨率。

### 候选气液输运验证（未接入主场景）

`python run.py phase-gpu`：生成 CPU fixture，并检查真实 GPU 三阶段守恒相分数输运。该测试使用给定速度，不代表已实现浮力或沙泡耦合。公式及限制见 [PHASE_TRANSPORT.md](docs/PHASE_TRANSPORT.md)。

### 交互气液候选窗口

`python run.py phase-view` 使用相同窗口宿主、鼠标旋转、暂停与资源调度展示 GPU 气液候选。它目前只有气液，不含沙粒耦合，不读取或覆盖正式存档。`python run.py app` 仍启动原沙画。`python run.py phase-smoke` 自动验证 256² 主窗口 5000 tick、旋转不重置、气体库存/边界与关闭，并输出截图。`python run.py phase-coupled` 做 CPU/GPU 耦合差分。

候选仍有界面细条纹，真实密度比、合并/分裂、沙反馈及自然节奏未验收。测试加速运行的每包 32 tick 不代表交互窗口速度；交互调度仍由现有预算模块控制。

`python run.py phase-topology` 检查 GPU 聚并、受拉伸断颈及两组对照，输出原始气体场图与连通区域统计。它不代表完整沙泡耦合通过。`python tests/analyze_phase_quality.py` 比较已保存的主窗口条纹修正前后原始场。

### 含沙气液候选

`python run.py phase-sand` 显示同一气液场中的三色沙，保留旋转/暂停及已有资源调度；仍为实验物理模型，使用独立候选存档，不加载或覆盖旧版正式存档。`python run.py phase-sand-smoke` 运行5000步主窗口验证；`python run.py phase-grains` 检查守恒排液交换与CPU参考逐字节一致；`python run.py phase-sand-benchmark` 测256/512 GPU成本。

该版本是占位/排液耦合，沙粒移动仍采用有效概率，压力/阻力尚未正确反馈到沙粒受力。不能将它称作完整双向流固耦合或已完成产品验收。详见 [SAND_FLUID_COUPLING.md](docs/SAND_FLUID_COUPLING.md)。

`python run.py grain-traction` 验证表面作用力估计和压力差改变沙粒运动方向。候选已加入这项移动反馈，但静止沙床载荷传递、移动边界冲量和接触网络仍未完成；不能称为完整受力耦合。

`python run.py grain-load` 检查多角度载荷守恒与GPU/CPU差分；`python run.py phase-load-response` 运行同初态的载荷启用/关闭对照。该标量近似已被静止载荷做功检查否决，当前phase-sand默认关闭它，详见 [GRAIN_LOAD_MODEL.md](docs/GRAIN_LOAD_MODEL.md)。

### 静止载荷诊断
`python run.py phase-static-work`：固定沙层、无气体8000步开关载荷对照。退出0只代表诊断执行成功；JSON中的 `static_load_model_rejected: true` 是物理失败证据。默认候选已禁用该载荷项，真实静止承载/移动边界耦合尚未实现。

`python run.py boundary-impulse`：检查固定沙粒/墙的原始反弹冲量与流体单步动量收支，包含Python/GPU对照。只覆盖静止几何，不代表移动颗粒双向耦合已经完成。

`python run.py moving-boundary`：规定切向壁速的CPU/GPU动量、做功与停壁衰减检查。固定占位，不代表已实现自由移动沙粒。

### 候选气液会话恢复
`python run.py phase-sand` 和 `phase-view` 分别读写各自的候选双槽存档。
Ctrl+S手动保存、120秒周期保存、正常关闭保存；重启恢复完整LBM分布和相场，
以及材料、tick、seed、角度、暂停和资源档位。旧版 `app` 存档不迁移、不覆盖。
`python run.py phase-sand --fresh-session` 可启动不读写任何会话的临时画面。
`python run.py phase-session` 检查真实GPU恢复继续演化、损坏回退及主窗口生命周期。
快照文件有模型版本和SHA-256；两个槽均无效时保留文件并禁用该次会话保存。
当前验证Windows/256²；更大网格保存延迟、崩溃/断电和macOS尚未验证。

### 实际主窗口长循环与气泡屏障
- `python run.py phase-cycle`：原双泡初态，50000tick、0/30/90/180/270°，输出 `reports/phase-cycle.json` 及截图。
- `python run.py phase-barrier`：7泡屏障临时画面，不读写会话。
- `python run.py phase-barrier --barrier-air-scale 1.25`：较多气量，仍只用于新建临时画面。
- `python run.py phase-barrier-cycle` 和追加 `--barrier-air-scale 1.25`：对应50000tick对照，分别写入不同报告前缀。
- `python run.py phase-initialization`：256/512初态守恒边界、相/沙不重叠、种子与共同颗粒场检查。
- 三组完成后 `python tests/phase_cycle_summary.py` 汇总释放位置统计。
这些是同一候选求解器的实际状态演化。较多气量延缓释放，但自然山形、完整物理耦合与视觉仍未通过验收。半径倍率不是实物注气体积单位。

`python tests/test_gravity_response.py` 输出512种子自由沉降的重力幅值统计；`phase-grains` 包含零/半/双幅值及零重力牵引GPU差分。默认重力不变，此检查不是物理单位标定。

### 有效沉降阻力对照
`python run.py phase-barrier --barrier-air-scale 1.25 --grain-drag 64` 使用临时会话观察较慢颗粒。
可选阻力倍率1/16/64/256，默认1；倍率64的长循环漏沙过慢，尚未推荐为产品默认。
`phase-barrier-cycle` 接受同一参数，报告带 `-drag64` 后缀。正常候选存档会保存阻力，恢复值优先于CLI新建参数。
流体数值舍入余量已纳入完整快照；旧格式读取保留原物理字段，新格式恢复同时保留余量。
# 当前物理验收补充

`python run.py phase-contact` 运行同一候选 Physics 的气泡托沙对照，输出
`reports/phase-contact-observation.json` 和 `reports/contact-*.png`。
退出 0 仅表示诊断完整性通过；气泡承载、反作用和自然释放仍未通过。
具体证据与下一验收条件见 [BUBBLE_CONTACT_ACCEPTANCE](docs/BUBBLE_CONTACT_ACCEPTANCE.md)。

随后运行 `python run.py phase-contact-ledger`，分叉上述测试状态，检查一步流体
动量变化、原始边界冲量、毛细力和浮力账目，并自动执行独立CPU参考验证。
该命令的退出码包含参考验证结果；它仍不证明移动颗粒接触力学已完成。

直接在主窗口观察较重沙层、气泡和旋转：

```powershell
python run.py phase-sand --contact-bed
```

这是临时接触观察场景，禁止恢复或保存用户作品；仍使用现有GPU求解器。
它不代表承载验收通过，下缘聚沙和接触反力仍待解决。


### 气泡下缘轨迹诊断（未修复物理）

`python run.py phase-contact-trace` 从临时contact-bed场景演化到10000 tick，再与无跟踪副本对照128 tick。输出 `reports/contact-motion-trace.json`，验证观测不改变完整物理状态，并记录每颗沙的身份、位移和实际驱动。退出0只表示轨迹诊断完整，不代表气泡承载通过；不会读写用户作品存档。

### 可见气泡—沙层候选（临时场景）

```powershell
python run.py phase-sand --contact-bed --energy-exchange --wetting-cosine=0.5
```

该实验窗口展示上方保留与两侧漏沙，可鼠标旋转。采用过阻尼能量交换近似，未验证完整水动力/接触载荷，不是正式默认模型；不读写作品存档。中性润湿对照会产生不合格沙壳，不能据此选为成品参数。

自动检查：`python run.py grain-energy-gpu`；实际窗口与翻转：`python run.py phase-sand-smoke --contact-bed --energy-exchange --wetting-cosine=0.5`；GPU时间戳：`python run.py grain-energy-benchmark`。

气泡行为检查：`python run.py energy-bubbles`。当前受控合并、拉伸分离、库存与释放对照通过；自由沙柱没有展示分裂，因此命令退出1。报告保留全部成功/失败样本，不能把失败解释为进程或设备故障，也不能宣称沙诱导分裂已完成。

有界集体回路实验：`python run.py phase-sand --contact-bed --collective-exchange --wetting-cosine=0.5`。最多8颗相接沙与旁侧流体同时沿相邻格回路移动；成本高于单粒候选，尚未展示沙诱导气泡分裂，保持非默认。内核差分：`python run.py grain-collective-gpu`。

集体活动门控检查与成对计时：`python run.py collective-activity`。检查静止/旋转唤醒、CPU/GPU候选计数和门控前后状态一致性；计时仅包含集体阶段。

材料干预对照：`python run.py energy-material-response`（可加 `--collective-exchange`）。同几何比较两种材料以及固定边界控制；材料同时改变重量和移动率，不是纯密度试验，也不构成气泡承载验收。

独立有效重量/移动率对照：`python run.py energy-parameter-response`，可加 `--collective-exchange`。保持同材料与同初态，每次只改变一个参数。

多气泡四轮长周期：`python run.py sandscape-cycle`。120000 tick临时世界与独立GPU重放，结果在reports/sandscape-long-cycle.json。当前数值完整性通过，但沙帽与气泡中部滞留仍是物理缺口。

混合浮升实验：`python run.py sandscape-preview --buoyant-exchange`；内核检查 `python run.py buoyant-transaction`，真实滞留状态续跑 `python run.py buoyant-continuation`。默认关闭，不能保存此实验模式；目前位移改善很小，尚未解决沙帽滞留。
