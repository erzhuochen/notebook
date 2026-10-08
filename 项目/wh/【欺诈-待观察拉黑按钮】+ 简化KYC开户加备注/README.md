# [43137786] 欺诈-待观察拉黑按钮 + 简化KYC开户加备注

> 状态：已确认
> 模块及适用范围：欺诈拉黑模块；全市场（四个区域部署各自独立）；熊猫汇款订单 + TopUp 充值订单
> 负责人：cze
> 最后更新：2026-10-08

## 两分钟回忆

- **为什么做**：欺诈分子常在注册后用同一台设备完成多个 KYC 再下单，造成资损。需要人工把可疑客户及其设备拉入名单，之后的订单要拦住、不能到账。
- **一句话方案**：在客户管理和 KYC 审查页加「欺诈-待观察拉黑」按钮，把客户的身份信息和全部设备号写入新表 `fraud_watch_list`。新欺诈规则 **QZ001** 在订单付款成功后的欺诈校验中比对名单，命中就写 `fraud_order` 拦截订单，等专员逐单放行。另外，简化 KYC 客户下单时给订单加一条备注。
- **核心链路**：运营点拉黑 → 名单写入身份行和设备行 → 客户（或同设备的其他账号）下单并付款成功 → 风控 MQ → `evaluateFraudRisk` → QZ001 命中 → 订单被拦截，申请单操作格变粉 → 专员在「本单欺诈信息」放行 → 订单继续清分。
- **最容易忘的细节**：
  - 规则编号是 `QZ001`。规则内容「客户被加入欺诈名单，待处理」，执行「等待相关人员确认」。
  - **只在付款成功后才触发**，只下单不付款不会拦。
  - 名单内客户整行显示黄色 `#FFE58F`（KYC 审查页、客户管理页）。被拦订单的申请单操作格显示粉色 `#fc89c3`。
  - 变粉依赖 **manager-data** 的 Nacos 配置 `common.risk.seriousFraudRule` 里包含 `QZ001`，没配就显示灰色。
  - 放行只对当前这一单有效，下一单还会被拦。
  - 简化 KYC 备注只针对 `kyc_status = 21（SHORT_KYC）`，而且是**覆盖**订单备注。
- **当时的取舍**：
  - 名单单独建表，没有复用 `system_black_list`（wt-order 下单时会被它直接拒单）和 `fraud_order`（标记行会污染现有查询）。
  - 设备号只记拉黑那一刻的快照，设备会变这一风险需求方已接受。
  - 仅注册、没有 KYC 的客户也可以拉黑，这时只记设备号和用户编号。
  - 拉黑前已经在途的订单不补拦。
- **当前待确认**：无

## 1. 背景、目标与范围

### 背景
欺诈分子往往在注册账户后，用同一个设备号完成 KYC，再创建订单。运营判断某客户存在可疑行为时，需要一个手工入口，把客户加入「欺诈-待观察」名单并记录其设备号，防止对应客户（以及用同一设备开的其他账号）的订单到账，造成资损。

后续变更：有些客户**仅注册、没做 KYC**，运营也需要按设备号拉黑，所以入口加到了客户管理页面。

### 目标
1. 运营可以在**客户管理**和 **KYC 审查**页面把客户加入或移出「欺诈-待观察」名单；名单内客户的行显示黄色。
2. 名单内客户、或与名单设备相同的用户，创建的订单在付款成功后被欺诈规则 QZ001 拦截，不能到账；申请单显示粉色，等专员人工放行。
3. 简化 KYC 开户的客户创建订单时，订单备注里提示「该客户为简化KYC开户时创建的订单，请留意。」

### 范围
- 包含：
  - 客户管理页（含英文版）和 KYC 审查页的拉黑、移出按钮，以及行变色。
  - 新名单表 `fraud_watch_list` 及其加入、移出接口。
  - 欺诈规则 QZ001（熊猫订单 type=0，TopUp 订单 type=1）。
  - 被拦订单的粉色展示、本单欺诈信息展示、人工放行，均沿用现有欺诈流程。
  - 新下单链路（`OrderServiceRefactor.commit`）里的简化 KYC 订单备注。
- 不包含：
  - 外包版客户管理页（`e_customer`）的按钮和变色。
  - KYC 档案页的名单标记。
  - TopUp 自己的 KYC 审核页。
  - 跨区域部署（prod / awsprod / sgprod / euprod）之间的名单同步。
  - TopUp App 采集的设备号（wt-risk 连不到 tp 库）。
  - 拉黑前已经在途的订单。
  - 旧下单链路（`/v2/client/commit`、`OrderV3Controller`）的简化 KYC 备注。
- 涉及的系统：wt-entity（规则枚举）、wt-risk（名单表、接口、QZ001）、wt-order（简化 KYC 备注）、manager-data、manager-shiro、manager-website。

## 2. 完整业务链路

| 步骤 | 触发者与触发时点 | 前置条件 | 系统动作 | 页面或数据结果 | 取消、失败或例外 |
| --- | --- | --- | --- | --- | --- |
| 1 | 运营在客户管理「更多 → 欺诈-待观察拉黑」，或在 KYC 审查行操作栏点人形图标 | 客户不在名单中；有 `root:customer:fraudWatchAdd` 权限 | 弹出确认框「当前操作会将客户加入欺诈黑名单，是否确认？」 | — | 点「取消」直接关闭，不写名单 |
| 2 | 运营点「确定」 | — | manager-shiro 转发到 manager-data，再通过 Feign 调 wt-risk `/risk/fraud/watch/add`。wt-risk 查 KYC：信息齐全就写 1 行身份行；查该用户在 `user_operate_info` 的全部设备号，每台写 1 行设备行；两者都没有时写 1 行空身份行兜底 | 客户管理提示「添加成功（身份信息 X 条、设备 Y 个）」，KYC 审查页提示「添加成功」；列表刷新后该行变黄 | 已在名单：「该客户已在欺诈待观察名单中」。查不到 KYC 不报错，只写设备 |
| 3 | 客户（或同设备的其他账号）下单 | — | 正常创建订单 | 订单 `TRANSACTION_ING` | 只下单不付款不会触发欺诈校验 |
| 4 | 订单付款成功（例如 AU 资金对账确认后发风控 MQ；TopUp 在 tp 结算成功后调 `/risk/tp/fraud`） | 源币种在 wt-order `riskMQSupportSourceCurrency` 内；没有被 `doRiskJudge` 的前置检查拦下 | `evaluateFraudRisk` 读 `fraud_config` 拿到 QZ001，执行 `QZ001.exec`，比对用户编号、身份串、下单用户全部设备号 | — | 本单已经有放行记录时整套欺诈规则跳过；规则执行异常只记日志，视为未命中 |
| 5 | QZ001 命中 | — | 写入 `fraud_order`（`order_id`=订单主键，`fraud_id`=QZ001，`fraud_pass_status`=1），覆盖订单 NOTE 为规则内容，并写备注历史；风控流程到此停止，不进合规和清分；美国订单额外发 signal REVIEW（沿用现有逻辑） | 申请单操作格变粉；订单详情「欺诈信息」tab 变粉；「本单欺诈信息」出现一行 QZ001「未放行」 | `seriousFraudRule` 未配 QZ001 时显示灰色 |
| 6 | 专员在订单详情「本单欺诈信息 → 欺诈放行」，填写放行原因 | — | `fraud_order` 改为 2（已放行），记录放行人、原因、时间；该订单继续清分 | 粉色消失，显示「已放行」 | 放行只对本单有效，客户下一单仍会被拦 |
| 7 | 运营在客户管理「更多 → 移出欺诈-待观察」，或 KYC 审查行操作栏的黄色人形图标 | 客户在名单中；有 `root:customer:fraudWatchRemove` 权限 | 弹出输入框填写原因；wt-risk 把该用户所有生效行改为 0（已移出），记录移出人、原因、时间 | 提示「移出成功」，行颜色恢复 | 不在名单：「该客户不在欺诈待观察名单中」。已被拦但未放行的订单**不会**自动放行 |
| 8 | 客户下单（新下单链路 `OrderServiceRefactor.commit` 的最后一步） | KYC 状态 = 21（SHORT_KYC） | 订单 NOTE 覆盖为「该客户为简化KYC开户时创建的订单，请留意。」，并写一条备注历史（`createBy=system`） | 订单备注和备注历史里可以看到这条提示 | 这一步失败只记日志，不影响下单；之后其他流程可能覆盖 NOTE，但备注历史保留 |

## 3. 具体规则

| 规则编号 | 触发时点 | 命中条件与匹配对象 | 处理动作 | 适用范围 | 例外及优先级 |
| --- | --- | --- | --- | --- | --- |
| QZ001 | 订单付款成功后的欺诈校验（`evaluateFraudRisk`）；TopUp 为 tp 结算成功后 | 名单中**生效**（status=1）的记录，满足任一条即命中：① `user_id` 等于下单用户；② 身份行内容等于下单人 KYC 拼出的「姓\|名\|yyyy-MM-dd\|证件号md5」；③ 设备行内容等于下单用户在 `user_operate_info` 里的**任一历史设备号** | 写 `fraud_order` 一行（未放行），覆盖订单 NOTE 为规则内容，写备注历史，返回拦截，不进合规和清分 | `fraud_config`：`ALL/ALL/QZ001/status=1`，type 0（熊猫）和 type 1（TopUp）各一行 | 订单已经有放行记录时，所有欺诈规则都跳过；下单人 KYC 身份信息不全时跳过身份比对；空设备号和无效设备号不参与比对 |
| 简化KYC备注 | 新下单链路 `OrderServiceRefactor.commit()` 末尾 | 下单人 `kyc_status = 21（SHORT_KYC）` | 订单 NOTE **覆盖**为「该客户为简化KYC开户时创建的订单，请留意。」，并写备注历史 | 所有走 `OrderServiceRefactor.commit` 的订单（所有市场的子类都会走到） | 只判断 21，不含 INIT / WAIT_IDENTITY_SUBMIT；旧链路不覆盖；失败不影响下单 |

**身份串的规范化规则**（拉黑和比对用同一套）：
- 姓、名：去掉所有空白，转大写。
- 出生日期：兼容 `yyyy-MM-dd`、`yyyy/MM/dd`、`yyyyMMdd`、`dd/MM/yyyy`、`dd-MM-yyyy`，以及带时间的写法，统一转成 `yyyy-MM-dd`。
- 证件号：直接用 KYC 行里现成的 `id_number_md5`。
- 四项中**任一为空就不生成身份串**，避免同名用户互相命中。

**无效设备号**（不写入、不比对）：空串、`null`、`undefined`、`unknown`、`0`、`00000000-0000-0000-0000-000000000000`。

## 4. 页面、字段与权限

### 页面交互

**客户管理**（`customerCenter/customer.htm` + `customer.js`）
- 入口在操作列的「更多」下拉里：
  - 不在名单时显示 112「欺诈-待观察拉黑」。
  - 在名单时显示 113「移出欺诈-待观察」。
- 拉黑：确认框文案「当前操作会将客户加入欺诈黑名单，是否确认？」，按钮为「确定 / 取消」；成功后提示后端返回的「添加成功（身份信息 X 条、设备 Y 个）」。
- 移出：输入框标题「移出欺诈-待观察名单，请输入原因」；成功后提示「移出成功」。
- 名单内的客户整行底色 `#FFE58F`；搜索和刷新后颜色保留。
- 英文版 `customerEn.js` 只有行变色，没有按钮。

**KYC 审查**（`customerCenter/kycExamination.htm` + `kycExamination.js`）
- 行操作栏图标：
  - 不在名单：普通人形图标「欺诈-待观察拉黑」。
  - 在名单：黄色人形图标「移出欺诈-待观察」。
- 确认框、原因输入框同客户管理；拉黑成功固定提示「添加成功」，不显示条数。
- 名单内的客户整行底色 `#FFE58F`，**优先于** EU 道琼斯状态的底色（`CHECKING` 为黄色 `#FFFF00`，`P_CHECKING` 为粉色 `#FF60AF`）。
- 调用的是客户管理的接口 `customerCenter/customer/fraudWatch/*`。

**申请单管理**（`orderCenter/applyOrder.htm` + `applyOrder.js`）
- 粉色只上在**操作列那一格**，不是整行。需要同时满足：
  - `status = TRANSACTION_ING`
  - `riskFlag` 为空
  - `fraudFlag <= 0`（`fraud_overview` 里没有该订单 `fraud_status=1` 的记录）
  - `fraudRelease = true`（有未放行的 `fraud_order` 记录）
  - `seriousFraudRelease = true`（该记录的 `fraud_id` 在 `seriousFraudRule` 里）
- 只满足前四条时显示灰色 `#B1BBC2B2`；`fraudFlag > 0` 时显示橙色 `#FFCA57`。
- `applyOrderEu` 和 `applyOrderJp` 两个同名页面**没有**欺诈着色逻辑；钱包订单列表也没有。
- 订单详情「本单欺诈信息」的规则内容、执行两列直接展示 `fraud_content` 和 `fraud_solution`，前端没有改。

### 数据字段

**名单表 `fraud_watch_list`**（wt 主库；wt-risk 读写，manager-data 只读）

| 字段 | 来源 | 何时记录或更新 | 用途 | 特殊说明 |
| --- | --- | --- | --- | --- |
| user_id | 页面传入的用户编号 | 加入时 | 按用户编号命中；列表变色 | 一个用户对应多行 |
| type | — | 加入时 | 1 = 身份行，2 = 设备行 | — |
| content | 身份行：KYC 拼成的身份串；设备行：`user_operate_info.unique_identification` | 加入时 | 比对 | 兜底行的 content 为空串 |
| status | — | 加入时为 1；移出时改为 0 | 只有 1 参与命中和变色 | 移出后可以重新加入，会新增一批行 |
| create_operator / create_time | 请求头 `mg-loginName` | 加入时 | 操作记录 | — |
| remove_operator / remove_reason / remove_time | `mg-loginName`；页面输入的原因 | 移出时 | 操作记录 | — |
| update_time | — | 加入、移出时 | — | — |

需求要求记录的「姓、名、出生日期、证件号」**合并成身份行的一个字段**，证件号只存 md5，不存明文。

**展示字段**（不落库）：客户管理行的 `Users.fraudWatch`、KYC 审查行的 `PayerV2Ext.fraudWatch`，取值 1 或 0。manager-data 每页按 userId 批量查一次名单表来填充。

**欺诈记录 `fraud_order`**（沿用现有表）：QZ001 命中时写入：
- `order_id`：订单**主键 ID**，不是 SEQ_NO。
- `fraud_id`：QZ001。
- `fraud_content`：规则内容。
- `fraud_solution`：执行。
- `fraud_pass_status`：1。
- 放行时更新 `fraud_pass_status=2`、`release_user`、`fraud_pass_reason`、`release_time`。

### 权限与操作记录

| 权限码 | 说明 | 控制的接口 |
| --- | --- | --- |
| `root:customer:fraudWatchAdd` | 欺诈-待观察拉黑 | `customerCenter/customer/fraudWatch/add` |
| `root:customer:fraudWatchRemove` | 移出欺诈-待观察 | `customerCenter/customer/fraudWatch/remove` |

- 客户管理和 KYC 审查两个入口用**同一组权限**。
- 外包角色没有入口。
- 放行沿用现有「欺诈放行」权限和流程。
- 拉黑和移出都记录操作人；移出另外记录原因。

## 5. 边界与异常

- **跨市场、跨设备、重复操作**：
  - 同一区域部署内，名单表和 `user_operate_info` 都不分市场，所以同一设备换个市场下单（例如 AU→CN 改成 EU→CN）也能命中。
  - 四个区域部署（prod / awsprod / sgprod / euprod）的数据库相互隔离，名单**不跨区域**。
  - 设备比对用下单用户的**全部历史设备**：用 A 设备注册、换 B 设备下单，也能命中。代价是家人共用设备等情况可能误伤，由人工放行兜底。
  - 已在名单中再次拉黑，提示「该客户已在欺诈待观察名单中」；页面上按钮也会切换成「移出」。
- **数据缺失或变化时**：
  - 仅注册没有 KYC，或 KYC 查询失败（例如 service-aukyc 不可用）：不写身份行，只写设备行。
  - 注册时没有采集到设备号：只能按用户编号拦截，即兜底的空身份行。
  - 设备号会变化：名单只存拉黑当时的快照，不会动态刷新。需求方已接受这个风险。
  - 多市场用户：身份行只按页面传入的国家码查一次 KYC。客户管理传注册国家，KYC 审查传该 KYC 行的国家，EU 国家统一转成 EUR。
  - 简化 KYC 状态 21 在客户补全完整 KYC 后会变，之后的订单不再加备注。
- **撤销、解除、放行或回退时**：
  - 移出名单后，已被拦、尚未放行的订单**不会自动放行**，仍需专员逐单处理。
  - 放行只针对本单；名单不变，客户下一单仍会被拦。
  - 拉黑前已经过欺诈校验的在途订单不补拦。
- **与其他规则同时命中时**：
  - 「本单欺诈信息」会列出多条规则；放行时按订单号把该订单的所有欺诈记录一起放行。
  - 订单有 `riskFlag`（合规风控），或在 `fraud_overview` 里被反欺诈拉黑时，操作格显示合规色或橙色，不显示粉色。
  - QZ001 不在 `fraud.risk.whiteListRule` 和 `autoFraudRule` 里，所以不会被系统自动放行。
- **覆盖不到的订单**（已知限制）：
  - 源币种不在 wt-order `riskMQSupportSourceCurrency` 里的订单不走风控 MQ，不会触发 QZ001。
  - TopUp 用户没有关联 Panda 账号时没有 Panda 订单副本，不会进 wt-risk；TopUp App 的设备号也查不到。
- **简化 KYC 备注被覆盖**：
  - 这条备注本身是**覆盖写**（`SET NOTE = ...`），会冲掉下单流程里先写入的备注，例如 AU BPAY 校验结果。
  - 之后清分路由备注、QZ001 等欺诈命中备注、支付流程也会覆盖或清空 NOTE。
  - 完整记录以备注历史为准。
- **已有问题（不在本需求修复范围）**：EUF22 往 `fraud_order` 写的 `order_id=0` 标记行会导致 `selectPushFraudOrder` 空指针，并误触发 USF06。建议另外立项修复。

## 6. 验收场景

| 场景 | 给定条件 | 执行操作 | 预期结果 |
| --- | --- | --- | --- |
| 正常拉黑（有 KYC） | 客户 KYC 完整，有 3 个设备 | 客户管理「更多 → 欺诈-待观察拉黑 → 确定」 | 提示「添加成功（身份信息 1 条、设备 3 个）」；名单表新增 4 行，status=1；客户管理和 KYC 审查两处该行都变黄 |
| 仅注册客户拉黑 | 客户没有 KYC，有 1 个注册设备 | 客户管理拉黑 | 提示「添加成功（身份信息 0 条、设备 1 个）」；名单表新增 1 行设备行 |
| 本人下单被拦 | 名单内客户 | 下单并付款成功 | `fraud_order` 新增 QZ001、未放行；订单备注为规则内容；申请单操作格变粉；本单欺诈信息显示 QZ001「未放行」；订单不清分 |
| 同设备新账号被拦 | 新账号使用了名单内的设备 | 完成 KYC，下单并付款成功 | 同上，被 QZ001 拦截 |
| 跨市场被拦 | 名单客户在同一区域部署内换市场下单 | 下单并付款成功 | 被 QZ001 拦截 |
| 放行 | 订单被 QZ001 拦截 | 本单欺诈信息「欺诈放行」并填写原因 | 状态变为已放行，粉色消失，订单继续清分；该客户下一单仍被拦 |
| 移出名单 | 名单内客户 | 「移出欺诈-待观察」并填写原因 | 提示「移出成功」，行颜色恢复；之后的订单不再被 QZ001 拦截 |
| 重复拉黑 | 客户已在名单中 | 调用拉黑接口 | 提示「该客户已在欺诈待观察名单中」，不新增记录 |
| 取消拉黑 | — | 在确认框点「取消」 | 弹窗关闭，名单不变 |
| 只下单不付款 | 名单内客户 | 只提交订单 | 不触发欺诈校验，不变粉（符合预期） |
| 简化 KYC 备注 | 客户 `kyc_status = 21` | 新链路下单 | 订单 NOTE 为「该客户为简化KYC开户时创建的订单，请留意。」，备注历史多一条 system 记录 |
| 非简化 KYC | 客户 KYC 已通过 | 下单 | 不加这条备注 |
| 未配 seriousFraudRule | QZ001 命中，但 manager-data 的 Nacos 配置里没有 QZ001 | 查看申请单 | 操作格显示灰色而不是粉色（用于检查配置是否漏配） |

## 7. 关键决定与待确认

### 关键决定
| 决定 | 原因或依据 | 放弃的方案 / 已接受的风险 |
| --- | --- | --- |
| 名单单独建表 `fraud_watch_list` | 与现有黑名单、反欺诈表的语义和读取方互不干扰 | 放弃 `system_black_list`（wt-order 下单时 `status!=0` 会直接拒单，违背"可下单、只拦到账"）；放弃 `fraud_order` 标记行（会污染 USF06、欺诈推送、历史欺诈弹窗等查询） |
| 一个用户一行身份 + 每台设备一行 | 按设备匹配可以走索引，不截断 | 放弃逗号拼接成一个字段（长度截断、无法建索引） |
| 命中条件：用户编号 / 身份串 / 设备号，任一即命中 | 覆盖本人跨市场、同设备多账号 | 身份串要求四项齐全，避免同名误伤 |
| 设备只存拉黑时的快照 | 需求方已确认设备号可能变更 | 不做动态刷新 |
| 每单都拦，放行只对本单有效 | 沿用现有 `evaluateFraudRisk` 按订单判断放行的语义 | 不做"放行一次就移出名单" |
| 允许无 KYC 的客户拉黑 | 需求变更：仅注册的设备也要能拉黑 | 只能按设备号和用户编号拦截 |
| 两个页面都放按钮，共用 `root:customer:*` 接口和权限 | 入口位置几经变化，最终两处都要 | 外包页不放 |
| 粉色复用现有 `seriousFraudRule` 机制 | 不改前端，和 USF03 等严重规则的展示一致 | 只有操作格变色，不是需求字面上的"整行粉色" |
| 规则内容「客户被加入欺诈名单，待处理」 | 入口有两个页面，文案不再写具体来源 | 放弃需求原文「客户在 KYC 审查时……」 |
| 简化 KYC 备注放在 `commit()` 末尾而不是 `commitAfter` | CHN、VNM、白标、TP 充值的子类重写了 `commitAfter` 且不调用父类 | 多查一次 KYC；旧下单链路不覆盖 |
| 拉黑前已在途的订单不补拦 | 需求写的是"尝试创建订单时拦截"；补拦要改订单状态机 | 拉黑前已过欺诈校验的订单可能到账 |
| 名单不跨区域部署同步 | 四个区域数据库隔离 | 跨区域的同设备订单拦不住 |

### 待确认
| 问题 | 为什么影响实施 | 需要谁确认 |
| --- | --- | --- |
| 行颜色 `#FFE58F` 是否可以 | 需求只写了"黄色"；要与 EU 道琼斯的 `#FFFF00` 区分开 | UI / 产品 |
| 简化 KYC 备注覆盖原备注是否可接受 | 当前代码 `SET NOTE = ...` 会冲掉 BPAY 校验等先写入的备注，只在备注历史保留；如果需要保留，要改成前置拼接 | 产品 |
| TopUp 订单的 Panda 副本是否会加简化 KYC 备注 | `RemitTypeOrderTpRecharge` 没有重写 `commit()`，理论上会走到，但没验证；需求是否期望 TopUp 订单也加 | 开发自测 + 产品 |

## 8. 原型与附件

| 内容 | 文件或链接 | 对应的需求步骤 |
| --- | --- | --- |
| KYC 审查页按钮位置 | ./assets/KYC审查-按钮位置.png | 步骤 1、7 |
| 拉黑确认弹窗 | ./assets/拉黑确认弹窗.png | 步骤 1、2 |
| 本单欺诈信息 / 欺诈放行 | ./assets/本单欺诈信息.png | 步骤 5、6 |
| 原始需求文档 | C:/Users/erzhuochen/Desktop/笔记/tem.md | — |

## 9. 变更记录

| 日期  | 改了什么 | 为什么改 | 影响哪些规则或场景 |
| --- | ---- | ---- | --------- |
| 2026-09-21 | 需求提出：KYC 审查加「欺诈-待观察拉黑」按钮，拉黑客户订单拦截变粉；简化 KYC 开户订单加备注 | 同设备多 KYC 的欺诈资损 | 全部 |
| 2026-09-28 | 初版实现：按钮放在 KYC 审查页；新建名单表、QZ001、简化 KYC 备注 | — | QZ001、简化KYC备注 |
| 2026-09-29 | 拉黑入口迁到客户管理（含英文版变色）；没有 KYC 也允许拉黑，只记设备；拉黑成功提示条数；权限码改为 `root:customer:*`；简化 KYC 备注只判断 SHORT_KYC，改为覆盖写 | 仅注册的客户也要能按设备号拉黑 | 步骤 1、2、8；仅注册客户场景 |
| 2026-10-08 | KYC 审查页按钮恢复，与客户管理共用接口和权限；规则内容改为「客户被加入欺诈名单，待处理」 | 两个页面都需要入口 | 步骤 1、7；页面交互 |

---

## 附录：实现与上线

### A. 各仓库改动（分支 `cze-43137786`）

| 仓库 | 改动 |
| --- | --- |
| wt-entity | `FraudRiskEnum` 新增 `QZ001`（「客户被加入欺诈名单，待处理」/「等待相关人员确认」） |
| wt-risk | 新增实体 `FraudWatchList`、`FraudWatchListMapper`（+XML）、`FraudWatchServiceImpl`（add / remove / findActiveHit）、`FraudWatchController`（`/risk/fraud/watch/add`、`/remove`）、规则 `QZ001` |
| wt-order | `OrderServiceRefactor.commit()` 末尾新增 `addShortKycOrderNote` |
| manager-data | `UsersController` 新增 `customerCenter/customer/fraudWatch/add`、`/remove`（Feign `RiskClient` 转发，操作人取 `mg-loginName`）；`Users` / `PayerV2Ext` 新增 `fraudWatch`；`UsersServiceImpl.selectCustomers` 和 `KycServiceImpl.selectKYCList` 每页批量填充；新增只读 `FraudWatchListMapper` |
| manager-shiro | `UsersController` / `UsersClient` 新增两个转发接口，加 `@RequiresPermissions` |
| manager-website | `customer.js`（下拉 112/113 + 行变色）、`customerEn.js`（行变色）、`kycExamination.htm/js`（行图标 + 行变色） |

### B. 建表语句

```sql
CREATE TABLE fraud_watch_list (
  id              BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id         BIGINT       NOT NULL COMMENT '被拉黑用户id',
  type            TINYINT      NOT NULL COMMENT '1身份(姓|名|yyyy-MM-dd|证件号md5) 2设备号',
  content         VARCHAR(255) NOT NULL,
  status          TINYINT      NOT NULL COMMENT '1生效 0已移出',
  create_operator VARCHAR(64),
  create_time     DATETIME,
  remove_operator VARCHAR(64),
  remove_reason   VARCHAR(255),
  remove_time     DATETIME,
  update_time     DATETIME,
  KEY idx_content_status (content, status),
  KEY idx_user_status (user_id, status)
) COMMENT '欺诈-待观察名单';
```

### C. 上线顺序

1. 建表（四个区域各自执行）。
2. 发布 entity jar。
3. 发布 wt-risk。第 7 步插入配置之前 QZ001 不会执行。
4. 发布 wt-order。
5. 发布 manager-data、manager-shiro、manager-website。
6. 在权限菜单配置两个权限码，并分配给对应角色：
   ```
   2000000,102-1-12,root:customer:fraudWatchAdd,欺诈-待观察拉黑,customer,fraudWatchAdd,/customerCenter/customer/fraudWatchAdd,3,0,1,
   2000001,102-1-13,root:customer:fraudWatchRemove,移出欺诈-待观察,customer,fraudWatchRemove,/customerCenter/customer/fraudWatchRemove,3,0,1,
   ```
   如果测试环境配过旧的 `121287` / `121288`（`root:kycDossier:fraudWatch*`），删掉。
7. `fraud_config` 插入两行：`source_country=ALL, target_country=ALL, support_fraud_id=QZ001, status=1`，`type` 分别为 0 和 1。
8. 在 **manager-data** 的 Nacos 配置中设置 `common.risk.seriousFraudRule=USF03,QZ001`，**保留 USF03**；这项配置热更新，不用重启。

### D. 排查速查（订单没被拦或没变粉）

```sql
SELECT ID, SEQ_NO, STATUS, PAYMENT_STATUS, RISK_FLAG, NOTE FROM apply_order WHERE SEQ_NO = ?;
SELECT * FROM fraud_watch_list WHERE user_id = ?;
SELECT * FROM fraud_order WHERE order_id = <订单ID>;
SELECT * FROM fraud_overview WHERE order_id = <订单ID> AND fraud_status = 1;
SELECT * FROM fraud_config WHERE status = 1 AND FIND_IN_SET('QZ001', support_fraud_id);
```

在 wt-risk 日志里用订单号依次搜下面这些关键字，看流程断在哪一步：
1. `风控校验`
2. `执行欺诈规则`
3. `go QZ001`
4. `命中欺诈待观察名单`
5. `QZ001规则执行异常`
6. `欺诈分控规则未放行`

前端：在申请单管理打开浏览器开发者工具，看 `listExt` 响应里这五个字段：`status`、`riskFlag`、`fraudFlag`、`fraudRelease`、`seriousFraudRelease`。

测试环境要跳过付款流程、单独验证 QZ001，可以调：

```
GET /risk/order/fraudOrderRisk/{订单ID}
```

它会直接执行 `evaluateFraudRisk`。
