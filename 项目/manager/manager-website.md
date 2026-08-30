我把一条真实的请求从「你点击页面」追到「数据库」全程验证了一遍。下面用这条线来讲整个项目。

---

# 一、三个仓库的关系

```
浏览器
  │
  ▼
manager-website      纯静态前端（layui + jQuery），没有构建、没有 Node
  │   所有请求写成 shiro:// 或 data:// 开头的"假 URL"
  ▼
manager-shiro        登录鉴权中心 + BFF 网关   :8091  /shiro
  │   ① 验 Session ② 验权限 ③ 转发（自己几乎不写业务）
  ▼
manager-data         真正的业务实现          :8092  /data
  │
  ▼
MySQL（11 套数据源） + 更下游的微服务（出款、清算、各国 KYC…）
```

一句话记住三者分工：

| 仓库            | 它负责                       | 它**不**负责                    |
| --------------- | ---------------------------- | ------------------------------- |
| manager-website | 长什么样、点了之后调哪个接口 | 任何业务规则                    |
| manager-shiro   | 你是谁、你能不能调这个接口   | 业务逻辑（转发而已）            |
| manager-data    | 业务逻辑、SQL                | 鉴权（信任 shiro 传来的用户头） |

> ⚠️ **对你最重要的一条**：你是 Java 实习生，日常改的 90% 在 `manager-data`。`manager-shiro` 你只会去加权限点和转发方法，`manager-website` 你只会去改字段展示。

---

# 二、一条请求的完整旅程（真实代码，可跟着点开）

场景：运营在后台打开「KYC 档案」页面，看到一张列表。

### 第 1 站 · 页面骨架

`manager-website/html/views/screen/customerCenter/kycDossier.htm`

纯 HTML，只有「检索表单」和一个空的表格容器。**它不含任何 JS 逻辑**。

### 第 2 站 · 页面控制器

`manager-website/html/static/js/controller/customerCenter/kycDossier.js:65`

```js
let tableIns = view.table('#dataList', 'shiro://customerCenter/kycDossier/list', {
    title: 'KYC档案',
    cols: cols,          // 表头定义
    done: function (res, curr, count) { ... }   // 数据回来之后做什么
});
```

**为什么 .htm 和 .js 能自动配对？** 因为 `layout.js:100` 这一行：

```js
layui.config({base: setter.base + "controller/", version: setter.version});
```

它把 layui 的模块根目录重定向到了 `controller/`。于是**同名路径自动对应**：

```
views/screen/customerCenter/kycDossier.htm
static/js/controller/customerCenter/kycDossier.js   ← 自动加载
views/tpl/customerCenter/*.tpl                      ← 弹窗模板
```

新增页面时这三处路径必须严格对应，写错一个字母页面就是白的（而且不报错）。

### 第 3 站 · 假 URL 被翻译成真 URL

`shiro://customerCenter/kycDossier/list` 不是浏览器认识的协议。`view.js:1253` 的 `view.prefix()` 在发请求前把它替换掉：

```
shiro://xxx  →  https://当前域名/shiro/xxx
data://xxx   →  https://当前域名/shiro/data-router/xxx   ← 注意，也走 shiro！
```

同时 `view.getHeaders()`（`view.js:191`）自动塞进鉴权头 `Authorization`。

**所以：永远用 `view.json()` / `view.table()`，不要自己写 `$.ajax`** ——自己写会丢掉前缀翻译和鉴权头，必然 401。

### 第 4 站 · 进入 manager-shiro

`manager-shiro/.../controller/data/KycController.java`

```java
@PostMapping("/list")
@RequiresPermissions("root:kycDossier:list")   // ← 唯一的业务价值
public ResEntity list(@RequestBody JSONObject commSearch) {
    return kycClient.list(commSearch);          // ← 原样转发
}
```

这就是那 120 个转发型 Controller 的长相。**它们只做一件事：卡权限。**

### 第 5 站 · Feign 找到下游

`manager-shiro/.../client/data/KycClient.java`

```java
@FeignClient(name = "service-manager-data", path = "data/customerCenter/kycDossier")
public interface KycClient {
    @PostMapping("/list")
    ResEntity list(@RequestBody JSONObject commSearch);
}
```

`service-manager-data` 是 **Nacos 里的服务名**，不是域名。Feign 去 Nacos 查到实例 IP 再发请求。

### 第 6 站 · 到达 manager-data

`manager-data/.../controller/KycController.java:235`

```java
@PostMapping("/list")
public ResEntity list(@RequestHeader(value = "mg-loginName", required = false) String mgLoginName,
                      @RequestBody CommSearch<PayerV2Ext> commSearch) {
    return kycService.selectKYCList(commSearch, mgLoginName);
}
```

注意 `mg-loginName` 这个请求头——**操作人是谁，是 shiro 转发时注入的**，manager-data 自己不做登录。

### 第 7 站 · Service 按国家分流

`manager-data/.../service/impl/KycServiceImpl.java:336`

```java
BaseKycBuilder baseKycBuilder = KycFactory.getFactory()
        .getBuilder(commSearch.getEntity().getCountryCode());
...
ResEntity<List<PayerV2Ext>> kycList = baseKycBuilder.selectKYCList(commSearch);
```

**这是这个项目最核心的业务模式**：同一个接口，澳洲、日本、欧洲、香港…走完全不同的实现类（`KycFactory` 注册了 11 个市场的 Builder）。

> 改 KYC 相关需求时，**第一个要问的问题永远是"改哪个国家"**。改错 Builder 等于没改。

### 第 8 站 · Mapper → SQL

Builder 里调 `mapper` 包下的接口，SQL 写在 `resources/mapper*/` 的 XML 里。

**这里有个大坑**：manager-data 有 **11 套数据源**，Mapper 接口在哪个 `mapperXxx` 包，XML 就必须放同名的 `resources/mapperXxx/` 目录。放错了会「接口能扫到、SQL 找不到」。

### 返回

数据原路返回，统一包成：

```json
{ "respCode": 0, "respMsg": "...", "entity": [...] }
```

前端只认这个结构：`respCode === 0` 正常，`1001` 登录失效。

---

# 三、前端语法扫盲（Java 视角）

你会看到的前端代码基本只有下面这几种句式，看懂就够用了。

### 3.1 每个控制器文件的固定外壳

```js
;layui.define(function (exports) {
    layui.use(["form", "layer", "table", 'view', 'tools'], function () {
        let $ = layui.$, view = layui.view, table = layui.table;
        // ... 真正的代码在这里
    });
});
```

逐行翻译成 Java 概念：

| 前端写法                  | Java 里的类比                                                                                                           |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| 开头那个孤零零的 `;`      | 没有对应概念。是**防御性写法**：万一上一个文件末尾漏了分号，多个 js 拼接时会语法错误，加个 `;` 兜底。**照抄就行，别删** |
| `layui.define(...)`       | 声明"我是一个模块"，约等于 `public class KycDossier {`                                                                  |
| `layui.use([依赖], 回调)` | 声明依赖 + 拿到依赖后执行。像 `@Autowired`，但**是异步的**：这些依赖要从网络下载，下载完才执行回调                      |
| `let $ = layui.$`         | 起别名，等价于 `import static`                                                                                          |

### 3.2 对象字面量 —— 前端的「Map」

```js
let tpl = {
    kycStatus: function (d) { ... },
    date: function (d) { ... }
};
```

这在 Java 里最接近：

```java
Map<String, Function<Row, String>> tpl = new HashMap<>();
tpl.put("kycStatus", d -> ...);
```

**关键认知：JS 里的「对象」本质就是 Map，属性名就是 key。** 所以下面两种写法完全等价：

```js
tpl.kycStatus      // 点号访问
tpl["kycStatus"]   // 中括号访问，key 可以是变量
```

### 3.3 最容易看懵的一句：`d[this.field]`

```js
let tpl = {
    kycStatus: function (d) {
        return tools.util.escapeSign('kycStatus', d[this.field]);
    }
};

let cols = [[
    {field: 'kycStatus', title: 'KYC状态', templet: tpl.kycStatus}
]];
```

拆开讲：

**① `templet: tpl.kycStatus` —— 把函数当值传**
注意**没有括号**，不是调用，是把函数本身传进去。类似 Java 8 的方法引用 `this::renderStatus`。layui 拿到这个函数后，**每渲染一行就调用一次**。

**② `d` 是什么？** 当前这一行的数据对象，比如 `{id: 1, userId: 88, kycStatus: 3}`。

**③ `this` 是什么？（重点）**
这是 JS 和 Java 最大的分歧。

> **Java**：`this` = 当前对象，在编译期就定死了。
> **JS**：`this` 取决于**函数是怎么被调用的**，同一个函数不同调用方式 `this` 不同。

layui 在调用 `templet` 时，把 `this` 绑定成了**这一列的配置对象**，也就是 `{field: 'kycStatus', title: 'KYC状态', ...}`。

所以 `this.field` === `'kycStatus'`，`d[this.field]` === `d['kycStatus']` === 这一行这一列的值。

**为什么绕这么一圈不直接写 `d.kycStatus`？** 因为这样同一个函数能复用给多列。`tpl.date` 就同时用在了「创建时间」「更新时间」等好几列上。

### 3.4 回调函数 —— 没有「等结果」这回事

```js
view.json("shiro://customerCenter/kycDossier/reRunKyc", {id: data.id}, function (res) {
    // 服务器返回后，才会执行到这里
    layer.msg(res.respMsg);
});
console.log("这一行会先执行！");
```

**JS 是单线程 + 异步的，网络请求不会阻塞。** 上面 `console.log` 会**先于**回调执行。

Java 类比：

```java
// 前端的行为约等于这个，而不是同步调用
future.thenAccept(res -> log.info(res.getRespMsg()));
```

**新手最常犯的错**：想让 ajax「返回」数据。

```js
// ❌ 永远拿不到，返回的是 undefined
function getList() {
    let result;
    view.json(url, {}, function (res) { result = res; });
    return result;   // 此刻请求还没回来
}

// ✅ 后续逻辑必须写在回调里
view.json(url, {}, function (res) {
    doSomething(res);
});
```

### 3.5 事件不写 onclick，写属性

HTML 里：
```html
<button lay-submit lay-filter="formSearch">搜索</button>
<a layadmin-event="detail">详情</a>
```

JS 里：
```js
form.on('submit(formSearch)', function (data) { ... });
```

思路和 Spring MVC 很像：**HTML 上贴个"路由标记"，JS 里按标记注册处理器**，双方通过字符串对应。改的时候两边名字必须一致。

### 3.6 `.tpl` 文件 = 前端版 JSP

```html
{{# layui.each(d.list, function(i, item){ }}
    <tr><td>{{ item.name }}</td></tr>
{{# }); }}
```

`{{ }}` 是取值，`{{# }}` 是写 JS 逻辑。作用等同于 Thymeleaf / JSP，用来拼弹窗和详情页的 HTML。

### 3.7 ⚠️ 没有编译器帮你兜底

这是从 Java 转过来最痛的一点：

```js
{field: 'kycStatuss', title: 'KYC状态'}   // 字段名多打了个 s
```

Java 会编译报错，**JS 什么都不会发生**——那一列就是空白，控制台也不报错。

所以前端排查问题的标准动作是：

1. **F12 → Network**：看请求的真实 URL 对不对、响应 JSON 里字段名是什么
2. **F12 → Console**：看有没有红色报错
3. 拿响应里的字段名去核对 `cols` 里的 `field` 拼写

另外还有个高频坑：后端新增了一个状态码（比如 `kycStatus = 9`），但没人去 `config.js` 的 `setter.constantPool` 里补对应的中文名，页面上这一列就显示**空白**。前端不报错，容易被当成后端 bug 查半天。

---

# 四、建议的阅读顺序


### 第 1 天：先跑起来，别读代码

1. 让 mentor 给你 **QA 环境的后台账号** 和 **Nacos 权限**（没有 Nacos，`manager-data` 和 `manager-shiro` 都起不来）
2. 浏览器打开后台，把菜单点一遍，心里对"这个系统在管什么"有个概念
3. 打开 F12 的 Network，随便点个列表页，看请求打到了哪个 URL、返回了什么

### 第 2 天：把上面那条 KYC 链路自己走一遍

按第二节的 8 站顺序，把 8 个文件依次点开对照。走完这一遍，整个项目的骨架你就有了。

### 第 3 天：读登录鉴权（因为这是最反直觉的部分）

`manager-shiro` 的这 4 个文件，按顺序读：

| 文件                        | 看什么                                            |
| ------------------------- | ---------------------------------------------- |
| `config/MySessionManager` | **sessionId 来自 `Authorization` 请求头，不是 Cookie** |
| `config/MyShiroRealm`     | 登录不用密码，用 **TOTP 动态码**，另外还有一条 SSO 分支            |
| `config/ShiroConfig`      | Shiro 过滤链的 `/**` = authc **被注释掉了**             |
| `config/MyInterceptor`    | 拦截未登录（`roleId == -1`）                          |

**这里有条必须记住的规矩**：因为全局 `authc` 是关掉的，**新增接口时忘了加 `@RequiresPermissions`，等于对所有登录用户开放**，Shiro 不会兜底。这是最容易在 code review 被打回的点。

### 第 1 周：吃透 manager-data 的两个模式

1. **多数据源**：11 套，`@Transactional` 必须显式写事务管理器名（如 `@Transactional("dev_dbTransactionManager")`），注入 `DataSource` 必须带 `@Qualifier`
2. **市场分流**：`factory/kyc/KycFactory` 的 11 个 Builder。**任何需求先确认是哪个国家**

同时**一定要读** `manager-data/docs/business-domain-primary-sources.md`。这份文档把 KYC/CDD、SOF/SOW、AUSTRAC 这些业务黑话映射到了具体代码位置，比读代码快十倍。里面还记了个陷阱：`/poli/*`、`poliNo` 这套命名已经是历史遗留，实际渠道可能根本不是 POLi，排障别只看字段名。

---

# 五、上手前必须知道的 4 件事

1. **没有测试可依赖。** manager-data 只有 5 个测试类，manager-shiro 只有 2 个。改完 `mvn test` 通过**不代表任何事**，必须起服务实测或走 QA。

2. **前端没有构建。** 改完 `.js` 直接刷浏览器，记得 Ctrl+F5 强刷绕过缓存。

3. **两个后端仓库不能互抄代码。** manager-shiro 是 Boot 2.7 + `javax.servlet`，manager-data 是 Boot 3.2 + `jakarta.servlet`，复制过去编译不过。

4. **配置全在 Nacos，不在代码里。** 在仓库里搜数据库地址是搜不到的。
