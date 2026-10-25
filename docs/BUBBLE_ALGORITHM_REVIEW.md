# 气泡算法重选：面向主应用的有限评审

核查日期：2026-10-24。状态：源码与许可证评审完成；候选尚未在本机移植或完成物理/性能验证。本文不表示气泡问题已修复。

## 当前失败及验收修正

主应用 `shaders/liquid_sand.glsl` 用气体邻居数量奖励交换，并设移动阈值。它没有连续速度、压力或气液界面应力；局部邻居奖励可能锁住界面。沙与气的关系主要是占位阻挡，不能充分表现沙载荷改变气泡、气泡变形改变漏沙路径的反馈。渲染平滑不改变这个事实。

现有守恒测试通过只能证明库存/边界等工程性质。小幅气体质心移动不是可见浮升验收，现有测试没有证明主应用中的合并、分裂和双向作用。继续调整黏聚常数不能替代建模。

## 已核查参考

GitHub API 的 pushed_at 是仓库最近推送时间，不等于最新功能发布日期或维护质量保证。完整 SHA、路径和源码检查记录见 reports/bubble-reference-audit.json 与 reports/bubble-source-inspection.json。

| 项目 | 核查结果 | 可借鉴内容与限制 |
|---|---|---|
| [CLIP](https://github.com/mshadkhah/CLIP) | BSD-3-Clause；未归档；最近推送 2025-05-31；SHA 111e1969388b6430350a30fa0551a7a9aefa8731 | `src/equation/NsAllen.cu` 实现守恒 Allen–Cahn 相场、化学势、界面法线、MRT 碰撞及力耦合。最直接的两相 GPU 算法参考。CUDA 不能直接运行于本机 AMD，也不是 Godot 插件。 |
| [taichi_LBM3D](https://github.com/yjhp1016/taichi_LBM3D) | MIT；未归档；最近推送 2025-04-07；SHA fe49e3f609b2038cbf93c8bd453ffc5c2bf98e4c | `2phase/lbm_solver_3d_2phase.py` 提供两相 color-gradient LBM、组分再分配及固壁处理。作为另一种界面算法对照；3D/Taichi 不能直接当作 2D GLSL 实现，其散射式累加也不能照搬成无同步的 shader 写入。 |
| [Aphros](https://github.com/cselab/aphros) | MIT；未归档；最近推送 2025-07-20；SHA b60ce3da52c19935fa24c778f62f02141eaf7f80 | PLIC VOF、表面张力与 Multi-VOF。`examples/202_coalescence/std.conf` 明确设置双气泡初态、两相密度/黏度、张力和压力投影。适合界面与聚并验证参考，完整 C++ 求解器不是低功耗 Godot 即插即用方案。 |
| [Particles4All](https://github.com/matsuoka-601/Particles4All) | MIT（API 元数据）；未归档；最近推送 2026-08-24；SHA 58d6fa6d2c50e3f58da5c7a6f9b885ce26c485f0 | WebGPU/PBF、粒子固体与流体交互可供后续参考；本次未做核心源码审计，也没有证明其为封闭气液两相气泡求解器，不作为本轮首选。 |

前三项已读取固定提交的 LICENSE；没有把第三方实现复制进产品。若移植代码，必须保留对应许可和归属记录。

## 算法判断

优先验证 **二维守恒相场 + LBM**，以 CLIP 为方程和步骤参考，重新实现 Godot GLSL 450 compute。这是候选选择，不是性能或真实性结论。相场描述每处气液比例，速度场搬运界面，表面张力影响形状，因而无需把气泡绑定为固定圆形对象。界面的连通分量可随动力学变化；浮升、变形、聚并、颈缩断裂仍需分别测试。

color-gradient LBM 保留为后备，不同时开发两套产品求解器。VOF 的清晰界面与守恒优势值得参考，但重建、压力求解和薄膜处理会增加当前工程范围。普通 PBF 水花效果不足以证明气泡物理正确。

特别注意：[Basilisk 的 no-coalescence 文档](https://basilisk.fr/src/no-coalescence.h) 说明，同一 VOF tracer 的界面距离达到网格尺度时会自动合并。这种数值拓扑变化不等于正确的液膜排液/破裂时机。相场也必须检查界面厚度及网格分辨率敏感性，不能以“碰到就合并”作为物理验收。分裂应由拉伸、剪切或受限通道中的颈缩产生，不能定时随机切泡。

## 接回完整目标的架构约束

- 气液场持有相分数、速度及 LBM 分布函数；沙粒仍保留独立材料身份和守恒库存。气体体积由相分数积分测量，不再用整数气体格数冒充精确流体守恒。
- 首轮采用二维有效模型，并明确薄玻璃间隙阻力/润湿是待标定近似；三维自由气泡的结果不能直接冒充流沙画。
- 液体运动给沙粒阻力；沙的占据率/运动向液体提供阻力及反作用。沙床必须影响气泡路径与形变。具体离散耦合需验证，不能把任意速度偏置当作双向动量耦合。
- GPU 采用 pull/gather、每格唯一写入、ping-pong 与 pass barrier；普通显示不读回完整状态。CPU 参考验证离散步骤，GPU 测试使用浮点容差及物理误差指标，不能要求浮点模型与旧整数模型逐字节相等。
- 旋转只改变局部重力；已有快照保留。新算法使用独立模型版本，不静默转换旧快照。新模型所有非派生分布函数必须纳入快照。
- 保留四模块边界。只在现有应用宿主接一个显式候选模式，验证完成前不替换用户正在运行的画面。不再扩展脱离产品的独立大型求解器研究。

## 下一实施阶段：有界主窗口验证

只实现一个 256² 候选，再测 512²；若失败，记录原因并停止增加功能，不能拿更高分辨率掩盖错误。

1. 无沙气泡：同一主窗口显示浮升、椭圆形变及重力反转；记录质心、气体积分、越界、速度上限和伪流。
2. 拓扑：分别设置接近双泡和受限拉伸气泡；观察连接/断裂，检查总气体积分连续性。增加不应马上聚并的近邻反例，比较两档网格和两档步长。
3. 沙耦合：相同初态有沙/无沙对照；改变沙床负载，验证泡形/路径和漏沙速率均发生合理变化。仅泡挡沙、沙不影响泡不算通过。
4. 完整主场景：任意角度旋转、暂停恢复、材料库存、封闭圆壁、持久状态均保持；主窗口直接观看，不用预录视频代替实时模拟。
5. 测 GPU 各 pass 与整步 p50/p95、每秒所需子步、显存及主窗口帧时。单步快不代表完成同等物理时间便宜；记录稳定性和界面误差后再决定是否采用。

进入上述实现前需写清离散公式、边界条件及守恒误差门槛。研究到此收敛为一个候选和可见验收，不扩展更多仓库名单。

## AMD 平台说明修正

AMD 提供 ROCm/HIP；CUDA 源码可评估 HIPIFY/HIP 移植，不能仅因项目使用 CUDA 就认定 AMD 无法使用。AMD HIP SDK 7.1.1 Windows 官方支持表包含 RX 7900 XTX（gfx1100）。这不代表 CLIP 已经移植或其所有依赖已支持。当前 PATH 与标准 Program Files/AMD/ROCm 位置未找到 HIP SDK，不据此断言整个磁盘没有 SDK，也未安装任何系统依赖。

官方依据：[Windows 支持表](https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.1.1/docs/shared/hipsdk/reference/system-requirements.html)、[CUDA 到 HIP 移植指南](https://rocm.docs.amd.com/projects/HIP/en/latest/how-to/hip_porting_guide.html)。当前 Godot Vulkan compute 已在 AMD GPU 上运行；保留 Vulkan 集成路线的原因是现有设备/渲染接口，而非 AMD 缺乏通用计算能力。是否引入 HIP，应比较参考求解器复用收益、原生扩展和数据互操作成本，不能未经测量假设 HIP 更快。

### CLIP HIP 静态移植审计（固定提交，未编译）

已检查上述固定 SHA 的全部 28 个 C/CUDA 头文件、实现及 CMake 文件，读取失败 0。API 清单保存于 reports/clip-hip-audit.json。发现的调用集中于 cudaMalloc/Free、Memcpy/ToSymbol、同步和错误处理；没有发现 cuBLAS/cuFFT/cuSPARSE/cuRAND 调用。CMake 显式使用 CXX/CUDA、CUDAToolkit、CUDA::cudart、Threads 以及 extended-lambda。源码使用设备 kernel、共享内存与线程同步。

结论：HIP 源码移植具有实际可行性，当前静态证据未显示大型 NVIDIA 专属数学库阻碍。尚需转换编译系统/宏/API，检查符号拷贝和 kernel 启动，构建并运行原始基准，随后处理 Godot 原生扩展与 GPU 资源互操作。静态名称扫描不能证明没有平台假设，也不是移植成功证明。本轮没有安装 SDK、修改驱动或复制第三方代码到产品。

当前决定：保留这条复用路线，不再以 AMD 作为排除理由；现有 Vulkan 候选进入共享主窗口做可见验证。若其密度近似或界面误差不能通过产品验收，应优先评估 CLIP 方程/实现的复用收益，不能继续无限扩展自研局部实验。
