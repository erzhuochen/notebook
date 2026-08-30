# manager-website 项目概览

> 面向 Java 后端开发的前端阅读笔记 · 基于 `cze` 分支（= release 同一提交）
> 讲法：把一条真实请求从「点击页面」追到「数据库」，用这条线串起整个项目。

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

### 第 0 站 · 整个前端只有一个宿主页

在进入具体页面之前，先搞清楚「一个页面是怎么被装载出来的」，否则后面每一站都会看不懂。

**完整装载链路：**

```
浏览器地址栏
  │
  ├─ index.html          320B，只有一行 meta refresh 跳转
  ▼
  ├─ index.htm           唯一宿主页：loading 动画 + <iframe id="main">
  │      │
  │      └─ 判断 tools.auth.read() 有没有 token
  │             │
  │             ├─ 无 → iframe 装 views/screen/login.htm（或 login_sso.htm）
  │             │        登录成功 → 存 token → 重载 index.htm → 再判断一次
  │             │
  │             └─ 有 → iframe 装 views/screen/index.htm  ← 主框架（导航+菜单+空内容区）
  │                          │
  │                          └─ hash 路由变化 → AJAX 拉取 xxx.htm
  │                                            → $(".welcome").html(内容)
  │                                            → 同时自动加载同名 controller/xxx.js
  ▼
  所有业务页面共享同一个 DOM、同一份 JS 运行时
```

#### ① 入口是 `index.html`，不是 `index.htm`

`index.html` 只有 320 字节，全部内容就是一行跳转：

```html
<meta http-equiv="refresh" content="0; URL=index.htm"/>
```

#### ② `index.htm` 是"壳"，本身不含任何业务界面

它的 `<body>` 里只有两样东西：

```html
<div class="loading-background" id="loading"> ... 熊猫 loading 动画 ... </div>
<iframe id="main" width="100%" height="100%"></iframe>
```

然后一进来就判断登录态，决定这个 iframe 装什么：

```js
view.json("shiro://loginState", function () {
    let main = $("#main");
    if (tools.auth.read()) {                    // 本地有 token
        let path = "views/screen/index.htm?r=" + Math.random();
        main.attr("src", route ? path + '#' + route : path);
    } else {                                     // 没 token
        view.json("shiro://judgeIp", function (res) {
            tools.auth.saveLoginUrl(res);
            main.attr("src", "views/screen/" + tools.auth.readLoginUrl());
        });
    }
});
```

**关键：登录页和主框架是同一个 iframe 轮流装的。**

- `shiro://judgeIp` 判断是不是外包客服的 IP，决定用普通登录页还是 SSO 登录页
- 登录成功发生在 `login.htm` 内部：存好 token 后重新加载 `index.htm`，第二次进来 `tools.auth.read()` 才有值，iframe 才换成主框架
- 另有一条 SSO 分支：URL 带 `?code=` 参数时走 `shiro://autoLogin`，登录完 `location.replace("index.htm")` 重走一遍判断

#### ③ 主框架 `views/screen/index.htm`：所有页面共用的骨架

```html
<div id="LAY_app">
    <div id="nav"></div>                        <!-- 顶部导航 -->
    <div class="layui-side" id="new_menu">      <!-- 左侧菜单 -->
        <ul id="LAY-system-side-menu"></ul>
    </div>
    <div class="layui-body" id="LAY_app_body">  <!-- 主体部分 -->
        <div class="layadmin-tabsbody-item layui-show welcome"></div>   <!-- 内容装这里 -->
    </div>
</div>
```

**注意：里面没有第二个 iframe。** 业务页面是被 AJAX 拉成 HTML 字符串后**塞进 `.welcome` 这个 div** 的，三级跳：

```js
// ① layout.js: render()
admin.init($(".welcome").empty(), url);          // 先清空，再加载

// ② admin.js:13 init()
layui.tools.timer.clearAllInterval();            // 清掉上个页面的定时器
admin.off();                                     // 解绑上个页面的事件
view(obj).render(url);

// ③ view.js:1353 render()
url = url + setter.engine;                       // setter.engine = '.htm'
$.ajax({url: url, dataType: "html", success: function (body) {
    container.html(body);                        // 把 HTML 字符串直接塞进 div
}});
```

因为外层 iframe 的 src 是 `views/screen/index.htm`，相对路径基准就在 `views/screen/`，所以 `admin.init(obj, "customerCenter/kycDossier")` 最终请求的就是 `views/screen/customerCenter/kycDossier.htm`。

**这是个真正的单页应用（SPA），路由靠 URL 的 hash（`#` 后面那段）驱动**，`index.htm` 里注册了 `window.onhashchange`。

#### ④ 由此推出的两个实际影响

**只有一个页面在 DOM 里。**
`.welcome` 是先 `empty()` 再填新内容，切页面时上一个页面整个被丢掉。这就是为什么 `admin.init` 第一件事是 `clearAllInterval()` 和 `admin.off()`——如果上个页面开了定时器或绑了全局事件不主动清掉，就会泄漏到下个页面，造成"我明明离开这个页面了，它还在发请求"的诡异现象。**自己写定时器时记得走 `layui.tools.timer`，别直接用 `setInterval`。**

**全局状态是共享的。**
所有页面的 JS 跑在同一个 iframe 的同一个 window 里。两个 controller 如果用了同名全局变量会互相覆盖。这就是每个 controller 都要用 `;layui.define(function(){...})` 包起来的原因——**那个函数壳的作用是造一个私有作用域**，把变量关在里面，相当于 Java 的类作用域。

---

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

**为什么 .htm 和 .js 能自动配对？**

```javascript
let setter = {  
    container: 'LAY_app' //容器ID  
    , version: '20210120'  
    , base: layui.cache.base //记录layuiAdmin文件夹所在路径  
    
    ...
}
```

因为 `layout.js:100` 这一行改变了 layui 的"查找规则"：

```js
layui.config({base: setter.base + "controller/", version: setter.version});
```

layui 是一个模块化框架，要加载一个模块时，它会去某个"根目录"下按名字找文件。这行代码把那个根目录改成了 `controller/`。

于是框架的逻辑就变成：当加载 `screen/customerCenter/kycDossier.htm` 这个页面时，自动去找 `controller/customerCenter/kycDossier.js`。路径后半段 `customerCenter/kycDossier` 两边**完全一样**，只是一个放在 `screen/` 下，一个放在 `controller/` 下。

这不是智能算法，就是**路径字符串必须完全一致**的一个约定。三个文件路径必须严格对应：

```
html/views/screen/<模块>/<页面>.htm         ← 页面骨架
html/static/js/controller/<模块>/<页面>.js  ← 逻辑代码（同名路径，自动加载）
html/views/tpl/<模块>/*.tpl                 ← 弹窗/详情模板（手动加载）
```

写错一个字母，框架找不到 JS 文件，页面空白——且**不报任何错误**，很容易让你以为是后端问题查半天。

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
