# 参考设计研究（2026-10-24）

## Clocktown / Godot-Falling-Sand-Compute-Shader
已读取 [README](https://github.com/Clocktown/Godot-Falling-Sand-Compute-Shader)、[sand.glsl](https://github.com/Clocktown/Godot-Falling-Sand-Compute-Shader/blob/main/sand.glsl)、[sand_simulator.gd](https://github.com/Clocktown/Godot-Falling-Sand-Compute-Shader/blob/main/sand_simulator.gd)。MIT。

借鉴 Margolus 2×2 独占分块、交替相位、dispatch barrier、固定物理调度和共享 GPU 纹理。其占据/移动掩码减少连续子步的速度偏差；本项目改为材料标签交换与任意方向重力，不移植其二值转移表。开口边界、鼠标补沙、浮点时间随机和像素视觉不适合本产品。作者性能数字不是本机测量；本版没有等价移动掩码，速度偏差必须验证。

## MaxBittker / sandspiel
已读取 [README](https://github.com/MaxBittker/sandspiel)、[lib.rs](https://github.com/MaxBittker/sandspiel/blob/master/crate/src/lib.rs)、[species.rs](https://github.com/MaxBittker/sandspiel/blob/master/crate/src/species.rs) 的 Cell、SandApi 和 update_sand。MIT。

借鉴紧凑材料状态、材料更新接口、粒子属性随状态移动和局部随机选择。Rust/WASM 粒子逻辑与 WebGL 显示/流体分工不是 Godot GPU compute；初始化包含 JS Math.random，不能直接继承严格种子复现承诺。M1 不迁移多材料游戏系统。

## 其余参考与兼容性
GitHub API 于 2026-10-24 核查：八个仓库均存在且 archived=false。下列日期是 pushed_at，不能单独证明维护质量或稳定性。

| 仓库 | 许可证元数据 | 最近推送 UTC | 本阶段评估 |
|---|---|---|---|
| [Clocktown](https://github.com/Clocktown/Godot-Falling-Sand-Compute-Shader) | MIT | 2026-03-25 | 同为 Godot 4.6；最直接参考，但 4.6.1 仍须本机验证 |
| [sandspiel](https://github.com/MaxBittker/sandspiel) | MIT | 2026-09-10 | 材料 API 概念适用，不是 Godot 插件 |
| [The Powder Toy](https://github.com/The-Powder-Toy/The-Powder-Toy) | GPL-3.0 | 2026-10-20 | 阅读 README/SAND.cpp；空气损耗、重力、碰撞参数分层有参考价值；复杂压力系统不直接迁移，不复制 GPL 源码 |
| [Powder-Sim](https://github.com/DeckardGer/Powder-Sim) | API 未识别许可证 | 2026-02-19 | 阅读 README/simulation.wgsl；研究分块、密度交换与阻力；无明确许可不复制源码，WGSL 也不能直接当 Godot shader |
| [WebGL Fluid Simulation](https://github.com/PavelDoGreat/WebGL-Fluid-Simulation) | MIT | 2024-11-12 | 阅读 README/script.js 的 advection、pressure 与迭代；多 pass 有成本，M1 不引入，后续要证明视觉收益 |
| [Lively](https://github.com/lively-community/lively) | GPL-3.0 | 2026-09-30 | 采用外部应用集成而非拷贝宿主源码；文档支持 Godot，但生命周期必须实测 |
| [live-wallpaper](https://github.com/ducbao414/live-wallpaper) | MIT | 2026-06-07 | README 是 macOS Ventura+ 视频壁纸/遮挡省电方案，不证明 Godot 实时集成 |
| [Aerial](https://github.com/AerialScreensaver/Aerial) | MIT | 2026-10-23 | 当前 README Aerial 4 要求 macOS26/Xcode16+，描述私有 WallpaperExtensionKit 与扩展进程，系统兼容风险须评估 |

Powder-Sim README 的每帧 pass 数描述不完全一致，不用其数字作性能基准；实际 shader 可见密度、概率移动、黏性限制和局部滑落，仅借鉴规则分解。macOS 两个参考本轮只做 README、许可与维护可行性筛选，未编译源码或验证原生生命周期。

[Lively Application Wallpaper](https://github.com/lively-community/lively/wiki/Application-Wallpaper) 文档提醒：Store 版本不支持 application wallpaper；由宿主管理尺寸/位置；不支持多窗口；应用壁纸暂停有特殊限制。M6 不能直接假设普通视频壁纸的暂停策略同样有效。

源码阅读定位（文件 blob SHA，不是仓库 commit）：
- Powder-Sim `src/simulation/shaders/simulation.wgsl`: `925b7ba6ee739c37252ce80e81c9e048040d53f9`
- WebGL fluid `script.js`: `d0db5af6bac342d9eb00205435d8b8997ebee815`
- Powder Toy `src/simulation/elements/SAND.cpp`: `b22ec36b2e1c50a60e97a865fbf82bb185d32d71`

## Godot 官方依据与依赖选择
[Compute shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html) 要求 RenderingDevice renderer。已核对 4.6 官方 RDShaderSource.source_compute、RDShaderSPIRV.compile_error_compute 和 RenderingDevice API；API 查证不等于代码运行验证。

采用 [Godot 4.6.1 官方发布](https://github.com/godotengine/godot-builds/releases/tag/4.6.1-stable) 作为固定基线，不声称最新或本机已安装。Windows x64 zip 官方 SHA256：`088da0457e2d1f7f8a45e6d4605a42b756ea33b9ccd75059bdbc01bb31c2b40d`。当前下载失败，无本地包校验。

项目实现原创，仅借鉴设计，未移植参考源码。未来复制 MIT 源码须保留 notice；GPL 与未确认许可证的源码不能无审查直接引入。
