# 模仿者卡槽领域模型

`Formation.imitaterSeedSlots` 是不可变 `Set<int>`，索引指向 `seedSlots` 中的灰卡。灰色和普通同种植物可以同时存在，比如 `seedSlots=['pea','pea']`、`imitaterSeedSlots={0}`。

真实原站证据由主协调者提供，已将观察事实转录至 `test/fixtures/parity/seed-imitater.json`：Imitater打开独立灰卡chooser；选择Peashooter_i产生iTenCard_0；普通Peashooter仍可同时选择产生TenCard_0；选择灰卡后Imitater sign=0，删除灰卡后恢复可选。此fixture是事实转录，不冒充原始浏览器HTML/截图。

构造、copy和fromJson均检查最多一个灰卡索引，且索引必须在现有卡槽范围内。fromJson另拒绝非整数、非数组及重复索引。模型复制输入集合，防止外部修改。

兼容策略：`toJson`仅在灰卡索引非空时写入新键，旧项目没有新键时默认空集合。空灰卡状态的旧JSON字段顺序及fingerprint保持一致。旧项目中的普通重复卡此前允许，因此不新增拒绝；新UI应在新增普通卡时阻止同种普通卡重复，并独立处理灰卡，不能以plant ID全局去重。

修改卡槽时，copy默认保留原灰卡索引。删除、重排或清空卡槽的调用者必须同时传入重编号后的集合；清空用 `copy(seedSlots: [], imitaterSeedSlots: {})`，不隐式猜测重编号或丢弃灰卡信息。新的同种normal/gray重复与所有历史普通重复均能无损保存。

验证：`dart test test/seed_domain_test.dart test/formation_test.dart test/original_catalog_test.dart`，30项通过；单独seed测试20项通过。`dart analyze lib/domain/formation.dart test/seed_domain_test.dart`无问题。覆盖源事实存取、不可变性、旧fingerprint、旧normal重复、copy/删除重编号、释放灰卡标记、最后合法索引及格式/边界错误。UI chooser和实际种植效果不在此领域阶段验收。
