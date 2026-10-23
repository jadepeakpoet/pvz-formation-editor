# 种植覆盖与叠加

这是布阵器，以快速编辑为准。按用户确认，不引入游戏的阳光、冷却、紫卡前置植物或严格地形禁种检查。

- 后放的普通植物替换同格旧主植物；不是把所有图层一起删除。
- 荷叶、花盆共用底座槽，补底座不删除主植物、南瓜和咖啡豆。
- 南瓜是独立外壳槽，咖啡豆是独立上层槽，可以与主植物、底座共存；咖啡豆只替换同格咖啡豆。
- 按用户已有要求，炮作为一个对象占两格；新对象与炮任一格冲突时清除整炮，花盆/荷叶例外。新炮横跨两株旧炮时都清除，保留底座，清除冲突南瓜、咖啡豆及梯子。
- 猫尾、缠绕水草、海蘑菇在水面不补荷叶；为它们添加外壳等对象也不重新补荷叶。
- 以上修改与自动补底座合成一次可撤销操作。重复点击同种植物的状态循环维持已有交互。

## 一手参考

- [jspvz 网页布阵器](http://jspvz.com/ArrayDesign/)及其[主脚本](http://jspvz.com/ArrayDesign/main.js)，2026-10-23获取。`oGd.add`（1173起）按 PKind 替换同类对象；模板把普通植物、Container、Shell、Addons 分开，Coffeebean 属于 Addons。它不要求升级前置植物，适合作为本布阵器的交互基准。
- [PvZ Portable](https://github.com/wszqkzqk/PvZ-Portable)，读取版本 `a46a1e8861fe7c91e02748b5743ff93f353b6cee`。`Board::GetPlantsOnLawn`（Board.cpp:2139）区分底座、主植物、南瓜和 Flying 槽；`Plant::IsFlying`（Plant.cpp:5119）识别咖啡豆。`Board::GetShovelButtonRect` 和 `DrawShovel` 提供顶部铲子区的原版位置、尺寸和相对偏移。只参考槽位和显示关系，不照搬游戏的种植合法性拦截；未引入或链接其 GPL 实现。

## 本地资源核对



