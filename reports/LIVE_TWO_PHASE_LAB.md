# 主设备实时两相实验

`python run.py live-lab` 打开独立实验窗口，旋转滑块改变容器局部重力并旋转显示，暂停按钮停止发起新步。物理状态连续保留；未替换默认三沙类工程原型。

新增 `live_cell.gd` 管理主 RenderingDevice 上的物理，`live_art.gd`/`live_color.glsl` 只读界面并输出 Texture2DRD；`live_lab.gd` 负责实验 UI 和有界调度。所有 RD 操作在渲染线程，不调用主设备 submit/sync。只允许一个步骤在途，没有积压队列；渲染上限 30 FPS，物理完成后才允许下一步。状态检查每步异步读回 16 字节，正常运行不读回整场。

## 真实检查

Godot 4.7.2 / Windows Vulkan Mobile / RX 7900 XTX：

- `python run.py lab-smoke` 完成 200 步、无量纲时间约 0.1，100 步后反转重力；与 CPU 参考最大体积分数差 2.008e-5，面积误差 6.10e-10，failures=0。
- 自动检查在途重复提交被拒绝，结束时仅一次完整物理网格读回；正常 200 步状态读回 3200 字节。
- 验证结束后再提交一步，在该步骤尚未完成时关闭；先解除共享纹理、等待回调、再释放 GPU 资源，进程正常退出 0，日志无错误。
- 完成延迟中位数 66.366 ms，包含主设备提交、渲染帧与回调等待，不能视为 GPU 执行耗时或利用率。当前每步仍预排最多 96 次压力循环，成本优化未完成。
- 69 项 CPU 测试及旧 GPU 1000 tick 守恒回归通过。新颜色 shader 通过主设备编译与实际截图检查。

截图 `live-lab-smoke.png` 已查看：圆形域内一个浅色气相区域、深色液相、旋转与暂停控件可见；32² 放大后明显粗糙，运动累计很短，绝非艺术质量验收或真实流沙画。

## 运行前提

依赖已有实验初始化 fixtures。缺少时先生成基础 pressure/geometric fixtures，再执行：

```powershell
python experiments/liquid/pressure_transport_fixtures.py
python experiments/liquid/buoyancy_fixtures.py --capillary-steps 200
python run.py lab-smoke
python run.py live-lab
```

初始气相采用解析圆面积，后续每帧只使用实时 GPU 状态；fixture 中的参考帧仅自动化 smoke 读取作比较，不参与正常显示或物理更新。

## 仍缺少

这是单泡两相实验，未接入沙粒接触、密度分层或气泡控制释放；壁面接触、多气泡、长稳、艺术外观和跨平台均未验收。交互滑块与暂停已实现，实机自动化只检查程序化重力反转，没有宣称完成鼠标拖动检查。下一步应测量真实 GPU 成本、收敛/备用曲率比例，并将颗粒与回流接入同一可观察实验。
