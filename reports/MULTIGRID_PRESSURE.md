# 多层 GPU 压力求解（2026-10-24）

## 实现

新增 `multigrid.py` CPU 参考、`multigrid_gpu.gd` GPU 调度，以及 `restrict.glsl` / `prolong.glsl`。复用原压力平滑 shader。细网格压力方程不变，通过 2×2 聚合构造 `A_coarse = P^T A_fine P`，限制残差、求粗层修正、延拓后继续平滑。三次前/后平滑，4² 粗层最多 32 次平滑。只聚合压力修正，绝不改变沙粒、气体或物理网格分辨率。

各层读写压力双缓冲；限制与延拓的 invocation 分别独占一个粗/细 cell；dispatch 之间 barrier。每次测试采用 CPU 已测的有限 V-cycle 数，不自动无限迭代。尚未在 GPU 上完成运行时残差归约和动态停止，因此不能作为完整自适应压力模块。

## 验证

- `python -m unittest discover -s tests -v`：**65/65 通过**。新增粗网格算子等价性、封闭变系数求解结果与原参考通量一致、迭代预算失败检查。
- `python experiments/liquid/multigrid_fixtures.py`：从原物理 fixture 构造多层输入，并以 CPU 最大残差 1e-8 决定有限循环数。
- `python run.py multigrid`：Godot 4.7.2 / Vulkan / RX 7900 XTX，**6/6 对照通过**，最大状态误差 2.43e-8、最大散度残差 2.15e-6，沿用原 GPU 2e-6 状态差 / 1e-5 散度门槛，未放宽。
- `python run.py liquid`：原 Jacobi 六组回归通过；`python run.py gpu`：原沙粒工程基线 1,000 tick 守恒通过。
- 首次运行发生 uniform set 的重复释放报错：外部 flux set 引用了多层输出 buffer，提前释放 buffer 会使它失效。修复为先释放外部引用，再释放多层资源。重跑 `reports/multigrid.log` / `reports/liquid.log` 已检查无 ERROR、SCRIPT ERROR、invalid ID。

## 工作量与探索性时间测量

| 物理输入 | Jacobi 压力 dispatch | 多层压力 dispatch | Jacobi GPU ms | 多层 GPU ms |
|---|---:|---:|---:|---:|
| 16² 沉降 | 2048 | 1776 | 4.476 | 3.648 |
| 16² 圆形浮升 | 2048 | 1632 | 4.316 | 3.407 |
| 16² 斜向变系数 | 2048 | 1632 | 4.444 | 3.236 |
| 32² 沉降 | 8192 | 3976 | 17.118 | 7.832 |
| 32² 估计曲率毛细输入 | 8192 | 2576 | 18.164 | 5.532 |

时间为每场景一个未预热 GPU timestamp 样本，含压力与最终面通量，不含 CPU 调度、初始化、读回、界面或渲染。**不是稳态 benchmark、GPU 利用率或产品性能保证**。两算法都通过相同 GPU 门槛，但原 Jacobi 固定循环会过度迭代；不能把这张表解释为相同最优停止策略下的算法速度比。

恒定曲率分解后的 RHS 为零，多层 CPU oracle 判定 0 循环，而原固定 Jacobi 仍跑 8,192 次；这组不用于有效速度比较。

## 未完成项

当前分片常数延拓较粗糙，收敛仍需 34–71 个 V-cycle。即使 32²，GPU 时间仍为数毫秒，且毛细演化需大量子步，远未满足桌面常驻预算。不能简单扩大到 256² 或 512²。

尚未将求解器接入主应用或 SurfaceCell 的完整 GPU 演化；动态系数/几何的层级更新、GPU 残差归约、温启动、更高效平滑/延拓、稳态多样本基准及错误恢复均待完成。主项目的物理与视觉验收未改变。

建议检查点：`experiment: add validated multilevel GPU pressure solver`。未自动提交 Git。
