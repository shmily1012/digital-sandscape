# GPU 压力到界面输运 — 2026-10-24

## 实现范围
把多层压力解、面速度计算、动态 CFL/散度检查和几何界面输运接入同一 GPU 命令链，dispatch 之间有 barrier，中间无 CPU 状态读回。压力右端仍来自外部实验输入，并非当前气泡/沙粒自动生成。

`transport_velocity.glsl` 计算 `u = source - M grad(p)`，归约最大向外通量与散度。只有压力收敛、输入有限且散度不超过 1e-5 才允许输运；步长为请求值与 `0.45 / max_outgoing_rate` 的较小值。拒绝时复制原界面至输出，不更新 Kahan 补偿。该门控仅覆盖当前两相输运，不是完整物理状态事务。

## 实测
Windows / Godot 4.7.2 / Vulkan Mobile / RX 7900 XTX，32²。

| 工况 | 结果 |
|---|---|
| 正向、反向，dt=0.02 | 接受，CPU/GPU 最大体积分数差小于 6.6e-8 |
| 请求 dt=1 | GPU 自动缩至 0.306820631，CPU 为 0.306821135；最大体积分数差 7.18e-7 |
| 外力 20 倍，128 次压力循环 | 未收敛，拒绝且状态逐字节保留 |
| 压力预算仅 1 次循环 | 拒绝且状态逐字节保留 |
| 面速度来源含 NaN | 拒绝且状态逐字节保留 |

六组检查 failures=0；圆形边界外始终为零。最大气相面积误差 2.26e-10；大时间步最大体积分数 1.000000238，位于既有 2e-6 数值容差内，未通过裁剪修正。

首次把 20 倍外力设为应接受工况时测试失败：128 次循环未达到绝对残差 2e-6。保留为拒绝回归，另以正常外力和较大请求步长验证 CFL。未提高残差门槛；该高外力求解能力仍未解决，也未据此断言失败原因一定是浮点精度下限。

回归：66 项 CPU 测试通过；5 组固定速度 GPU 几何输运对照通过；旧 GPU 沙粒原型 1000 tick 检查通过。旧原型结果不作为新液体物理的证据。

## 重现
已有基础 fixtures 时：

```powershell
python experiments/liquid/pressure_transport_fixtures.py
python run.py pressure-transport
python -m unittest discover -s tests -v
python run.py geometric
python run.py gpu
```

缺少基础 fixtures 时，先依次运行 `experiments/liquid/fixtures.py`、`experiments/liquid/multigrid_fixtures.py`、`experiments/liquid/geometric_fixtures.py`。

## 未完成与下一步
当前是 local RenderingDevice 的单步差分实验，没有主设备跨帧提交、在线曲率、三材料接触或动态生成的相间驱动力。未测完整链路稳定 GPU 时间，不声称达到桌面资源预算。应先接入持续状态与失败恢复，验证多步压力/界面反馈，再接入曲率与颗粒作用。主窗口仍保留旧工程原型，产品物理和视觉未验收。

## 后续验证：持续状态与拒绝后恢复

`python experiments/liquid/pressure_transport_fixtures.py` 现在同时生成连续序列；`python run.py continuous-transport` 在同一组压力和界面缓冲上执行 20 步正向、1 次 NaN 输入拒绝、20 步反向。没有重新初始化界面；压力保持温启动。失败步骤的体积分数和 Kahan 补偿逐字节不变，接受步累计时间约 0.8（实验无量纲时间），拒绝步不推进时间。

41 步检查通过，最大 CPU/GPU 体积分数差 1.78815e-6，最大气相面积误差 5.2471e-10。每一步检查圆外零状态、体积分数界限及累计时间。测试允许同步读回用于核验，不能作为生产每帧读回的实现模板。该测试是外部驱动的持续输运，尚无界面对压力右端的反馈，也不证明沙粒与气泡漏流正确。

修复接口风险：一旦更新动态面速度，禁止再次调用依赖初始化 CFL 缓存的固定速度接口；测试逐步验证被拒绝且不改变输出缓冲选择。5 组固定速度 GPU 回归、66 项 CPU 测试与旧 1000 tick GPU 检查通过。下一步仍需主设备事务集成和真实状态驱动力，不能以这些持续性检查替代完整物理验收。
