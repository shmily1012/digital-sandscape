# 物理重审阶段报告

日期：2026-10-24。

## 本轮完成
查阅厂家 Airscale/FAQ、Stokes 沉降和 Young–Laplace 界面资料、浸没颗粒失稳论文公开摘要；区分厂家观察、基础理论、未标定假设。对照 shader 指出无液体状态、无气泡、未校准材料概率和不依赖接触/坡度的伪摩擦阈值。重写物理优先级，设计三个可证伪的小实验，详见 docs/PHYSICS_REASSESSMENT.md。

实现独立 Python 诊断，不修改产品求解器：单球低 Re 极限的数值/解析对照、单一球形气液界面能量差分对照，以及旧规则的无接触单粒横漂反例。

## 已执行
- `python tests/physics_reassessment.py`：两项解析极限检查通过；旧模型各材料 54/64 seeds 出现无接触横漂，定位非物理扩散。
- `python -m unittest discover -s tests -v`：11/11 通过，约 4.24 秒。
- `python run.py gpu`：70 tick CPU/GPU 一致和 1,000 tick 守恒回归通过，failures=0。

前两项解析检查不代表动态气泡模型已实现；旧测试通过不反驳物理模型缺陷。数据在 physics-reassessment.json。

## 当前结论与下一步
旧版本只能叫 GPU 落沙工程基线。液体/气泡/接触机制的真实性未通过，不应继续以 renderer 改善掩盖物理不足。600 tick 的截图也未检测静止，不能称作已经测量的最终稳态。

下一步按 E1 沉降→E3 接触/有限库存局部供沙→E2 可变气泡层释放的顺序实现独立实验；E2 是集成产品的必要门槛。气泡具体闭合模型与实物参数尚未知，不能承诺已弄清全部机理。实物视频/数据校准仍缺失，但不阻碍先做基础极限与数值收敛实验。

建议 checkpoint：`docs: reassess three-phase physics and add falsification probes`。未提交 Git，未改主 shader、系统设置或原有运行会话。
