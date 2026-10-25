# Digital Sandscape

Godot 4.7.2 / Windows 的实时生成式流沙画开发原型。

## Windows便携包

[下载便携原型](dist/Digital-Sandscape-Windows-Prototype-20261025-085427.zip)。解压后双击 `Start Digital Sandscape.cmd`，无需Python或另装Godot。当前包未启动验证；物理限制见下文。

## 开发目录启动

双击根目录 **Digital Sandscape.cmd**，或运行：

```powershell
python run.py app
```

在 Godot 编辑器打开 `project.godot` 后运行，也使用同一多气泡作品场景。
项目使用 `.tools/godot-4.7.2` 内的便携版 Godot，不需要全局安装依赖。

## 操作与保存

- 鼠标拖动或使用滑块旋转；空格暂停/继续。
- F10 切换无边框摆件；右键拖动摆件窗口；F9 切换置顶；Esc 恢复边框（本次新增，未运行验证）。
- A 开关自动翻转；M 开关慢速模式；手动旋转立即退出自动模式。默认启动为手动模式。
- Ctrl+S 保存；每120秒及正常退出时也会保存。
- 下次启动恢复气液、沙粒、姿态和模拟进度。
- `python run.py app --fresh-session --seed=123` 创建临时作品，不覆盖原存档。

作品使用真实 GPU 状态演化，不是视频。旧模型的存档与当前作品分开保存。

## 当前交付范围

已提供圆形容器、黑灰白沙、多气泡合并与局部漏沙、连续旋转、堆积、完整存档与基础资源调度。

**这是开发原型，尚未达到最终物理与视觉验收。** 气泡与残留沙帽可能长期滞留中部，自然沙诱导分裂尚未实现，颗粒与界面仍粗糙。Windows独立安装包、macOS、壁纸和屏保集成未完成。

按用户最新要求，收尾阶段不再运行测试。本次入口统一与文档调整未作运行验证；历史测试通过不能替代本次验证。

当前功能、未验证改动与剩余工作统一见 [交付状态](docs/DELIVERY_STATUS.md)。

## 工程资料

[产品规格](docs/PRODUCT_SPEC.md) · [架构](docs/ARCHITECTURE.md) · [开发计划](docs/ROADMAP.md) · [阶段记录](reports/PHASE_REPORT.md)

旧基线显式启动：`python run.py legacy-app`。历史实验保留在 [实验说明归档](docs/EXPERIMENT_COMMANDS_HISTORY.md)，不再作为日常启动入口。

自动模式采用定时节奏：默认累计等待10分钟，再用15秒转动180°；慢速模式等待30分钟、转动60秒。暂停、GPU任务等待和休眠不会触发补赶翻转，因此实际间隔可能更长。这不是沉降检测；自动模式暂不随存档恢复。可在Godot项目设置 application_settings/rotation/appreciation_seconds 调整基础等待时间（60–86400秒）。本次新增功能未运行验证。

内部沙粒会在没有正交气液邻居时提前退出候选计算；这是未运行差分验证的优化，尚无性能收益测量。邻居移开后仍可继续运动，未冻结整个上层沙床。
