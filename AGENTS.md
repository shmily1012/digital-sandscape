# Digital Sandscape 工程约定

- 先读 docs/PRODUCT_SPEC.md、docs/ARCHITECTURE.md、docs/ROADMAP.md 和 reports/PHASE_REPORT.md。根目录同名文档仅作入口。
- 使用已验证的 Godot 4.7.2 / GDScript / GLSL 450（原规划 4.6.1 尚未实测）。四模块边界必须保留。
- 粒子状态只能由 Physics Engine 初始化或演化。旋转、导演、渲染和资源降档不得清空/重生成物理场。
- compute 必须保证无交叠写入、dispatch 间 barrier、各材料计数守恒和封闭边界。
- 随机数依赖显式种子与 tick，不依赖 TIME、系统时间或全局 randomize。
- 正常渲染禁止逐帧 GPU→CPU 读回；测试可同步。线程操作遵循 RenderingDevice 所有权。
- 不在工作负载增加时自动提高分辨率；所有 catch-up 和异步队列有上限。
- 每阶段提供变更、自动化结果、未验证项和下一步。CPU 测试不等于 GPU 测试，未跑测试不得报通过。
- 不引入视频或预生成山脉冒充实时模拟。不从参考项目直接复制未记录授权的代码。
- 运行 `python -m unittest discover -s tests -v`；具备 Godot 时运行 README 的真实 GPU 检查。修改 shader 时必须比较 GPU 与参考模型。
- 不自动修改系统驱动、电源设置、桌面注册表或壁纸，不全局安装依赖。
