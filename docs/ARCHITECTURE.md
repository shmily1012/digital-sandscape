> 当前交付与模块状态以 [DELIVERY_STATUS.md](DELIVERY_STATUS.md) 为准。下文含历史方案，旧M1性能数据及未接入候选不代表默认产品。

## 当前主入口（2026-10-25）

Godot默认sandscape.tscn → src/sandscape.gd，复用现有四模块与EnergyStateManager；默认多气泡持久作品。main.tscn与旧基线保留为显式诊断。此次入口调整按用户要求未运行验证。

# Digital Sandscape 架构

## 有界集体回路实验（2026-10-25）

`grain_collective_enabled` 默认为false，仅在显式临时能量场景启用。48颜色调度最多8颗轴向接触沙与旁侧连通液体组成相邻格回路，按整个回路势能差决定运动。复用能量核的状态、随机种子、tick与移动标记，无正常帧读回。只对存在旁侧液体路径的局部集体运动有效，不包含整床应力求解；增加的调度成本尚未证明值得作为默认。详见PHASE_REPORT最新记录。


## 临时过阻尼能量交换路径（2026-10-25）

`PhaseFluid.grain_energy_enabled` 切换内部运动核，复用当前气液相场、Renderer、Director与资源调度。只在显式contact-bed临时窗口启用，默认关闭。16颜色串行dispatch、颜色内不交叠读写；额外uint移动时间戳占4 bytes/cell。与旧牵引驱动互斥，paired interface只用于现有流体应力/润湿；不能将其总动量描述为已闭合。能量差交换保留完整流体包与材料，属于有效排液近似，非解析不可压补液。存档与跨平台仍未支持此实验模型。行为/预算证据及局限见最新PHASE_REPORT。


## 当前相场的有限界面功（只读候选，2026-10-25）

`shaders/grain_interface_work.glsl` 在既有PhaseFluid的相分数/材料上计算四个相邻流体交换的界面能差，输出vec4工作量与uint合法邻居掩码。仅唯一写入输出，无输入修改、世界提交或渲染接入。固液半格能最小化与现有Robin润湿边界一致；CPU全场能差/逆交换与GPU差分分别验证。该模块尚未加入压力、黏性、接触功，因此不能作为完整移动规则，也不能与旧traction直接相加。详见PHASE_REPORT最新记录。


## 分区GPU算子候选（2026-10-25）

`src/cut_cell_pressure.gd` 在该算子上增加有界CG候选压力迭代（1–256槽位，默认128）。向量更新、归约和算子调用均在GPU完成，最后重新计算 A*x 验证原始残差及反力有限性，再条件写入 `solution` 与 `solution_force`；barrier后才递增 `accepted_generation[0]`。失败保留压力、反力和版本号。版本0表示尚无有效配对，版本仅属于当前冻结拓扑实例，调用者必须等待所属RD工作包完成/屏障，不能当作跨队列无锁读取协议。继承的 `force/output` 始终是scratch，不能用于世界提交。版本达到uint32最大值时拒绝新发布而不回绕。

无动态拓扑、接触/气体状态提交或逐帧读回。默认float32门槛1e-6，不等同CPU端点1e-12容量验收。递推残差变小时会在预算内重新计算A*x，未达标则保留压力、重建搜索方向继续；复核和更新都占原槽位，不额外增加预算。solve_status新增更新/重启/复核计数。最终验证仍强制执行并将控制状态置为完成或拒绝；未引入预条件或GPU耗时调度。固定槽位仍会提交dispatch，但收敛/拒绝后的迭代算子在GPU上跳过；仍不能用计数代替耗时测量。

`cut-cell-precision`实测四个可解场景均达到1e-8；1e-9仅两个达到，另两个安全拒绝。所有成功均有CPU根据GPU压力独立验算；这不是完整物理步的容量验收。双精度参考压力舍入float32后的残差用于诊断表示误差，不被解释为数学精度下界。

冻结拓扑初始化检查边权对称性并构造连通分量CSR。`dt=0`纯压力流动时，GPU逐分量归约体积源，按逐节点残差容差及浮点求和误差界检查源项和；不相容标志为2，禁止迭代更新和压力发布，不减源项均值。`dt>0`压力/颗粒惯性联合算子不套用此判据：区域压力可通过颗粒运动平衡体积源。连通分量当前仍由CPU在测试拓扑初始化时构造，非GPU动态分区能力。

`src/cut_cell_operator.gd` 封装冻结分区的 CSR 拓扑与双pass GLSL算子，作为 Physics 内部候选，不接管主应用。输入分区压力、图边、边界权重、质量和自由速度；输出压力反力、`(L+dt S M^-1 S^T)p` 与 `S v`。调用者持有 RenderingDevice 线程与同步责任，record 不提交/sync/读回、不更改世界状态。CSR在分配前验证索引和所有权，dispatch之间显式barrier，每个输出唯一写入。

当前CPU构造拓扑仅用于 `python run.py cut-cell-gpu` 的GPU差分测试。动态拓扑、完整接触求解、保守气量输运和状态提交尚未迁入此模块，不能在正常渲染里通过逐帧读回弥补。四模块及旧运行时边界保持不变。

## 模块和数据流
Host → AestheticDirector（姿态/控制意图）→ 固定 tick 调度 → Physics Engine（状态唯一写入者）→ ArtRenderer（只读外观）。AdaptiveResourceManager 决定何时更新，不写粒子。

- `src/main.gd`：薄窗口宿主，鼠标拖动、滑块、暂停、生命周期和模块连接。未来自动交互增加时再提取 InteractionController。
- `src/physics_engine.gd`：主应用启用六材料液体/气体格点候选，双 R32_UINT 纹理在 phase 间交替、完整 tick 回到固定 state RID。旧 M1 单纹理仍保留供基线测试；统一管理 shader、uniform set、pipeline 和 tick。
- `src/randomness_manager.gd`：显式种子与整数哈希初始化；GPU 遵循相同 hash 规范，不使用墙钟随机数。
- `src/art_renderer.gd`：只读材料场，生成边长为物理场两倍的 RGBA8 展示纹理；局部矿物混色、气泡覆盖率和静态微纹理只影响显示。V 可切回直接颜色视图。Canvas shader 做玻璃与容器姿态采样；样式切换不更新物理。
- `src/aesthetic_director.gd`：Natural 默认，当前只处理手动姿态与局部重力。未来导演只调整合法物理条件，不能替换山脉。
- `src/adaptive_resource_manager.gd`：有界调度和低负载策略。完整 GPU 测量与预算 UI 留在 M4。
- `src/simulation_state_manager.gd` 已提供版本化、SHA-256 校验的双槽完整快照；仅 Physics Engine 从验证过的字节初始化 GPU 场。启动/手动/120 秒周期/关闭已接入；跨平台故障恢复仍需测试。PlatformIntegration 在 M6 接入桌面、壁纸和屏保。

## 数据和物理算法
以下记录旧基线的实际实现；其物理解释已被重审。新求解器尚未选型或接入，候选数据与线程约束见 PHYSICS_REASSESSMENT.md，不能把本文的“摩擦阈值”视为已验证摩擦模型。

R32_UINT 二维状态纹理：0 隐式液体/可占据空间、1 黑沙、2 灰沙、3 白沙、4 不可移动墙。圆外初始化为墙。每 invocation 独占 2×2 区域，phase 0/1 交替原点偏移，两次 dispatch 之间 explicit barrier，无原子争抢或交叠写入。因此本算法可原地更新，无需 ping-pong。

重力使用 `R(-angle)*(0,1)`，转换为幅值 32767 的整数向量。块内 sand→empty 候选先过粗略摩擦阈值，再按正投影加权抽样，最后按材料移动概率接受。每块每相最多一次交换；材料身份和计数守恒。算法有网格各向异性与相位速度偏差，详见 PHYSICS_MODEL.md，不能当作连续介质。

计数器随机数只依赖 seed/tick/phase/block，shader 状态演化使用整数。CPU 三角函数量化在极端边界仍可能跨平台舍入不同，不承诺所有硬件位级一致。重放以模拟 tick 的输入为准，不以墙钟时长为准。

## GPU 所有权与显示
生产使用主 RenderingDevice，所有 RD 操作提交到 Godot render thread。ArtRenderer 的 colorize pass 只读状态，输出 RGBA8；Texture2DRD 直接共享 GPU 纹理，无每帧整场读回。Canvas 逆旋转采样局部状态，配合逆旋转局部重力，使世界屏幕重力保持向下。玻璃、细颗粒与边缘抗锯齿不能写回物理或制造山脉。

shader 以源码运行时编译，错误写日志并停止初始化。发行导出时必须确保原始 GLSL 被包含，M6 验证；当前运行方式是工程目录。主设备不调用 submit/sync；GPU 差分测试使用 local RD，允许显式 submit/sync 和读回。

单个 render-thread 工作包在途；主线程通过 deferred callback 接收完成 tick，避免无限积压。退出先解除 Texture2DRD，再在 render thread 释放 uniform sets、pipelines、textures 和 shaders，之后退出。M4 处理设备丢失恢复，不能静默重新生成世界。

## 时间和资源
每 tick 固定 1/30 秒；前台目标 30 Hz 物理/60 FPS 渲染，后台 5 Hz/10 FPS，继续缓慢演化。累积 delta 上限 0.1 秒，每帧最多两个 tick；过载允许模拟时间慢于墙钟，不爆发补帧。

frame delta 只是负载代理：先降渲染到 30 FPS，再严重过载时将物理逐渐降至最低 15 Hz；两秒调节、十秒稳定恢复探测。它不是 GPU 耗时或利用率。M4 才加入实际 GPU 时间戳、电池/温度/前台应用/遮挡信号与预算档位，UI 明确区分目标、估计和测量。

默认状态尺寸 256²，启动可选 512²/1024²。状态+显示纹理理论分别占 0.5/2/8 MiB，不含运行时、驱动和帧缓冲。窗口输出尺寸独立。禁止降档时静默改网格或丢粒子。

## 持久性与平台
M1 持久性指会话内 GPU 状态，不含跨进程恢复。M5 快照必须含 schema/algorithm version、尺寸、seed、完整材料/气泡字节、tick、angle、参数、校验和，支持原子替换。种子不能替代完整存档。

当前验证基线 Godot 4.7.2 Standard/GDScript，Windows Vulkan Mobile renderer；原规划 4.6.1 未实测。Compatibility/OpenGL 不支持 compute。macOS 需实测 RD backend、R32_UINT storage image、RGBA8 storage/sampling、同步、导出签名；目前未验证。

未来 DesktopHost/WallpaperHost 管理窗口层级、显示器、可见性、电源和输入，复用物理/渲染接口。Windows Lively 外部宿主与 macOS 原生集成分别处理生命周期；Godot 导出不能被当作原生壁纸支持。


接触与载液共同参考模型的数据/方程和 GPU 尚未覆盖的边界见 [COUPLED_CONTACT_MODEL.md](COUPLED_CONTACT_MODEL.md)。该 CPU 实验尚未接入主应用。

## 气液候选窗口（2026-10-24）

`phase_preview.gd` 继承主窗口宿主，复用 Director 和 AdaptiveResourceManager。
`phase_fluid.gd` 是候选 Physics 组件，唯一初始化/推进相分数与 LBM 分布；
`phase_art.gd` 仅读取相分数输出 Texture2DRD。两者均在主 RenderingDevice
所属渲染线程操作。主线程仅提交一次有界工作包；普通显示不读回物理场。
测试读回、截图和加速包属于 phase_preview_smoke，不属于正常运行路径。

候选入口 `python run.py phase-view` 尚无沙粒，不读写正式会话文件，不取代
默认 app。候选完整存档需要记录相分数、全部分布函数及版本，当前未实现。
该窗口只用于把新求解器的实际行为带回应用交互验收，不是完成版流沙画。


`phase-sand` 在候选Physics中启用共享材料缓冲和两阶段保守颗粒交换。
材料同时作为LBM/相输运边界输入；移动交换完整流体分布及相分数，Renderer
只读颜色。`phase-view`保留气液对照模式，二者均不迁移旧存档。
当前仅几何排液耦合，详见 SAND_FLUID_COUPLING.md 的受力反馈限制。

## Candidate checkpoint integration (2026-10-24)

The candidate host `phase_preview.gd` now uses `phase_state_manager.gd`, a separate
binary two-slot journal with model ID `phase-boussinesq-voxel-v1`. It shares the
host lifecycle but never reads legacy app saves. Payload order is active c (4n²),
active postcollision f (36n²), material (4n²), boundary velocity (8n²), and
rest-population rounding residual (4n², mass_compensation=true). Legacy payloads
without this flagged extension initialize only the new residual to zero. Tick parity
is preserved and both ping-pong buffers are initialized from the active state.
Scratch/derived fields are rebuilt before use. The current interactive model uses
zero prescribed wall velocity; nonzero wall snapshots are rejected until geometry
motion is implemented. Future equation/schema changes must revise the model ID.

Capture/restore runs only on the RD owning thread. Validation and journal writes
run on one IO worker, with no RD access. A pending save prevents additional physics
submissions and additional checkpoint tasks. Closing during a save is deferred,
then the final state is captured and written before teardown completes. Render/UI
remain active during IO; bounded scheduling avoids a catch-up burst. Loading still
validates on the main thread before GPU initialization. Large-grid latency and
hardware crash durability are unverified. Snapshot integrity is not physics validity.

## 有效模型参数分离（2026-10-25）

PhaseFluid的grain_weight_scale只乘颗粒重力功，grain_mobility_scale只缩放颗粒动力学移动率。默认均1；参数仅用于临时能量交换候选，push constant原尾部空位传递，无新GPU缓冲。集体回路液体阻力保持独立。此配置尚未纳入正式存档，不能据参数响应宣称完整接触压力闭合。

集体回路revision 2：较高侧向通路被挡时，每侧截取仍有完整相邻液体回路的最长下段，最少2颗、最多8颗；活动门控同步覆盖下段。该修复不扩展接触网络或补入整床压力载荷。

## 多气泡作品入口（2026-10-25）

`PhaseFluid.sandscape_fields`仅用于新作品初始化：保留既有沙材料数组，由显式种子生成不等半径/间距的9个气泡。`sandscape-preview`复用phase_preview宿主、能量交换物理与现有渲染/资源模块，不生成沉积轮廓。临时模式禁止存档，旋转不调用初始化；版本标识seeded-irregular-bubbles-v1。GPU状态演化与普通运行无读回约束保持。

## 多气泡持久会话（2026-10-25）

EnergyStateManager通过独立模型标识和目录复用双槽journal，payload为60 bytes/cell，包含energy移动标记；metadata保存所有运动参数与算法revision。PhaseFluid.restore_energy仅接收已验证payload，先恢复模型配置再初始化状态与缓冲。宿主默认sandscape持久、preview临时，旧模型不迁移；GPU读回限checkpoint，IO worker不操作RenderingDevice。新接口不改变历史snapshot_bytes的56-byte布局及其测试用途。

## GPU混合浮升候选（临时，2026-10-25）

BuoyantLoopTransaction每tick对一列串行搜索有界混合物质回路，单invocation写入且阶段间barrier。只读取GPU当前状态，交换完整包，复用energy移动标记。它在液体更新后、单粒更新前执行；默认关闭，正式持久入口不允许开启。列轮询和主轴选向是当前限制，尚无完整动量闭合；只观察到很小的滞留改善。
