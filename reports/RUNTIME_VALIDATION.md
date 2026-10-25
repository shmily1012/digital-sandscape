# Godot 4.7.2 实机验证 — 2026-10-24

本报告更新 PHASE_REPORT.md 的环境阻塞状态。用户提供 `C:\Users\Sasha\Downloads\Godot_v4.7.2-stable_win64.exe.zip`，解压到项目 `.tools/godot-4.7.2/`，未全局安装。

## 环境
- 可执行返回 `4.7.2.stable.official.ed1daf0bf`。
- 实际启动日志：Vulkan 1.4.359 / Forward Mobile / AMD Radeon RX 7900 XTX。
- 初次运行不能写用户 AppData；改用项目内 portable editor marker 与子进程 APPDATA/LOCALAPPDATA 后解决。系统环境未改变。
- 仍有 `Failed to read the root certificate store` 环境错误。离线 GPU/窗口测试正常；未改证书、安全策略或网络配置。

## 修改
新增 run.py 项目本地启动器、主窗口 smoke test 和 GPU timestamp 小基准。修复鼠标输入：使用事件中的坐标并转换为 Control 局部坐标，避免读取异步鼠标当前位置导致事件重放不可靠。物理 shader 规则未改变。

## 验证结果
| 检查 | 结果 | 范围 |
|---|---|---|
| GDScript 调度器 | failures=0 | 前台 30 Hz、暂停、后台 5 Hz、有界补帧和过载降档 |
| 实际 GPU 差分 | failures=0 | 32² seed709，70 tick 连续改角度，GPU 与 CPU fixture 字节一致 |
| 实际 GPU 长序列 | failures=0 | 共 1,000 tick，逐 tick 改角度，各材料计数与墙边界守恒 |
| 主窗口 256² | failures=0 | 760 tick，真实主 RD、颜色转换、Canvas、鼠标注入、暂停旋转、缩放、翻转、退出 |
| 主窗口 512² | failures=0 | 同上，持续使用原状态 RID |

256² 材料数：黑 4,793 / 灰 4,973 / 白 4,897；512²：黑 19,862 / 灰 20,087 / 白 19,714。改变角度/窗口尺寸没有重新初始化世界。测试期间显式暂停调度，再有界执行 tick 以取得可重复截图；这不等同长时间自然观看测试。

机器可读证据：gpu-validation.json、app-smoke-256.json、app-smoke-512.json、gpu-benchmark.json。日志保留每次执行输出；初始有失败的鼠标测试已修复并复测。

## GPU 小基准
使用 local RD，10 帧预热、60 个样本，每样本执行一个物理 tick（两相）+ colorize，submit/sync 只用于测试。时间取 GPU timestamps。

| 网格 | GPU p50 | GPU p95 | GPU max | 两张纹理理论容量 |
|---|---:|---:|---:|---:|
| 256² | 0.01020 ms | 0.01036 ms | 0.01044 ms | 0.5 MiB |
| 512² | 0.02816 ms | 0.02876 ms | 0.02908 ms | 2 MiB |

这些数据不含窗口 Canvas 绘制、完整应用开销、CPU/GPU 调度、电池、驱动和运行时显存，不是百分比利用率或正式 60 秒长测。UI 仍显示 GPU cost unmeasured，因它没有持续在线测量；不得把此离线小基准伪装成实时监测。

## 视觉检查与 M1 状态
已查看真实应用的沉降和翻转截图：圆形框、单色材料、粒子移动均可见；颗粒仍明显偏粗，当前沉降轮廓呈盆形，尚不具备参考实物的细流、多峰和稳定层次。M1 的工程运行/守恒部分通过，**“自然山脉”视觉验收仍未达标**。未声称完整 M1 产品效果完成，也未提前实现 M2。

下一步建议进入小范围 M2 物理实验：功能气泡/释放缝隙、有效液体阻力、滑落规则和网格方向偏差。先改善沙粒释放与堆积原因，再投入 M3 渲染；提高分辨率本身不会解决山脉形状。macOS、完整存档、前台应用干扰与长稳仍待验证。

建议 checkpoint：`fix: validate Godot 4.7.2 GPU path and event-based rotation`。本轮未提交 Git。
