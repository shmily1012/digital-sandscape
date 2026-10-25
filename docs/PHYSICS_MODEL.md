> 当前交付与模块状态以 [DELIVERY_STATUS.md](DELIVERY_STATUS.md) 为准。下文含历史方案，旧M1性能数据及未接入候选不代表默认产品。

> 当前主应用采用 `shaders/liquid_sand.glsl` 的六材料守恒格点近似；默认启用气体/液体交换、气体邻域内聚偏好、无支撑轴向沉降与受支撑侧滑。不是完整液体压力或表面张力求解器。下文原 M1 模型为历史基线；当前范围与验收见 [DELIVERY_PLAN.md](DELIVERY_PLAN.md) 和 [阶段报告](../reports/PHASE_REPORT.md)。

# M1 物理模型与验证边界

> 重审后，此文件仅描述旧工程基线。其方向阈值不是接触/安息角模型，移动概率不是已验证的液体阻力。产品物理方案及三个实验见 [PHYSICS_REASSESSMENT.md](PHYSICS_REASSESSMENT.md)。

## 状态与坐标
N×N 的 uint32 网格，0=隐式液体/可占据空间，1=深沙、2=灰沙、3=浅沙，4=密封墙。圆心在像素中心坐标 N/2，判定使用整数：`(2x+1-N)²+(2y+1-N)² <= (N-8)²`。圆外墙永久固定。M1 不存储液体压力或气泡；0 并不是已实现流体的证明。

种子初始化只运行一次：容器上部放置略稀疏的交替材料层，底部没有预定义山脉。同一状态用于此后所有旋转。数据中保留每种材料标签，不能用颜色像素反馈代替材料状态。256²→512² 只能重启新会话时显式选，不在运行时丢弃粒子缩放。

## 一次固定 tick
1. phase 0 独占 2×2 块，phase 1 将块原点移到 (-1,-1)，两次 dispatch 间 barrier。
2. 每块四个 cell 仅由该 invocation 访问；越界视为墙，永不写越界坐标。
3. 枚举块内 sand→0 候选；方向位移 d 需满足 `dot(d,g) > 6000 * (abs(dx)+abs(dy))`。这是粗略安息角启发阈值，不是已标定的安息角定律。
4. 用正重力投影作为权重作整数 reservoir 抽样。seed/tick/phase/block 确定所有随机选择。
5. 黑/灰/白有效移动概率分别 210/256、155/256、105/256，模拟不同阻力下的沉降差异；这些是未标定参数，不是实际矿物密度。
6. 接受时只交换材料与液体空位；一个块每相最多一次交换。因此每种材料精确守恒，无原子写入竞争。

每 tick 的模型时间固定 1/30 秒。实际每秒执行 tick 数降低时世界缓慢演化，不通过扩大单步或补跳过去的时间追赶。主机 UI 记录角度，下一批物理用对应局部重力；姿态变化不会重新分配状态纹理。

## 已知近似
- 没有粒子惯性、旋转角速度冲量、浮升气泡、反向流体耦合和沙间密度交换。
- 阻力概率不等同于液体仿真；不能把 M1 视为真实流沙画完成版。
- 网格的 2×2 限制与相位更新产生方向/速度偏差；任意角度输入不代表任意方向无偏。
- CPU 48² 云团、30 tick、seed=908 的方向探针最大偏差约 11.418°（120° 输入）。该数值仅是特定小样本诊断；M2 目标是更大样本下中位角误差 <5°，未达标。
- 尚未以高分辨率实际画面确认山峰、细流或安静观感；CPU 静止堆积不等于视觉验收。

## M2 气泡方案
先让独立 bubble occupancy/连通气泡区域提供阻挡与浮升规则；气泡与液体位点交换，沙流需通过可用缝隙。功能气泡先验证沙释放节奏，再由 ArtRenderer 生成圆润边缘与反射。气泡和沙的每次交换都需同一无竞争调度与各材料守恒规则。不要将视觉泡泡当作功能模型。

## 测试分层
Python 标准库参考模型验证物理不变量，包含块执行顺序反转验证。真实 Godot GPU 测试生成相同初始场与 70 tick 旋转序列，读回与 CPU fixture 按字节比较。主应用不运行 CPU 模型，也不使用读回路径。方向探针、1,000 tick 连续改变姿态的守恒测试不等于 1,000 次完整沉降循环的新颖性分析。

## Candidate bubble-barrier initial conditions (2026-10-24)

The candidate now has an opt-in seven-bubble row for new temporary worlds. It
reuses the baseline material array byte for byte, then initializes gas only in
fluid cells. Centers depend on the explicit seed; no runtime time/random source
is used. This is an initial condition, never a reset after rotation or a generated
mountain. Radius multipliers 1 and 1.25 yield different gas inventories and release
rates under identical dynamics. No fluid constants or material mobility were tuned.

The product mechanism motivating this test is described in the KB Collection
retailer's [knowledge center](https://movingsandart.com/pages/all-moving-sand-art):
air acts as a barrier regulating sand release. This supports testing the mechanism,
not a quantitative physical validation of our field model or its time scale.
See phase-cycle-comparison.json for actual GPU results. The original two-bubble
scene and row scene are not precisely matched in gas inventory. The two row cases
share grain locations, classes, seed and solver parameters, and differ in gas radius.

Long runs retain a basin-like deposit and unrealistically regular small bubbles.
No arbitrary rearrangement, artificial splitting or hidden particle teleportation
was added to improve the image. Bubble rise versus grain settling, contact slopes,
and physically justified load feedback remain unresolved.
