# 跨域 (CORS)

## 概述

### 什么是跨域

浏览器的**同源策略**规定：只有 **协议、域名、端口** 三者完全相同才算同源。任何一项不同，就是跨域。

| 当前页面 | 目标接口 | 是否跨域 | 原因 |
|----------|----------|----------|------|
| `http://a.com/index.html` | `http://a.com/api/user` | 否 | 完全同源 |
| `http://a.com` | `https://a.com` | **是** | 协议不同 |
| `http://a.com` | `http://api.a.com` | **是** | 域名不同（子域也算） |
| `http://a.com` | `http://a.com:8080` | **是** | 端口不同 |

### 最关键的一个认知

**跨域限制是浏览器的行为，不是服务器的。**

请求其实**已经发出去了，服务器也正常执行了业务逻辑**（数据库该改的都改了），只是浏览器发现响应头里没有许可，就拒绝把响应内容交给 JavaScript，并在控制台报错。

由此可以推出三条实用结论：

- **Postman、curl 调接口永远不会跨域** —— 它们不是浏览器，没有同源策略
- **服务端之间互相调用不存在跨域问题** —— 后端调后端不经过浏览器
- **报跨域错误不代表接口没被执行** —— 非幂等接口（如下单）可能已经生效了

### 为什么要有同源策略

假设没有它：你登录了网银，Cookie 存在浏览器里。此时打开一个恶意网站，它的 JS 就能直接请求网银接口并读取余额、发起转账 —— 因为浏览器会自动带上你的 Cookie。同源策略正是为了阻断这种攻击。

## 核心概念

### 简单请求与预检请求

浏览器把跨域请求分成两类，处理方式完全不同。

**简单请求**需要同时满足：

- 方法为 `GET` / `HEAD` / `POST`
- `Content-Type` 只能是 `text/plain`、`multipart/form-data`、`application/x-www-form-urlencoded`
- 没有自定义请求头

不满足任意一条，就是**预检请求**。

> **实际工作中的重点**：前端用 axios 发 JSON 时 `Content-Type: application/json`，或者带了 `Authorization` 头 —— 这两种情况都不满足简单请求条件。所以**生产项目里绝大多数接口都会触发预检**。

### 预检流程

预检会在真实请求之前，先自动发一个 `OPTIONS` 请求去问服务器「我能不能发这个请求」：

```
1. 浏览器自动发 OPTIONS
   OPTIONS /api/order HTTP/1.1
   Origin: https://www.example.com
   Access-Control-Request-Method: POST
   Access-Control-Request-Headers: content-type, authorization

2. 服务器响应许可（不走业务逻辑）
   HTTP/1.1 204 No Content
   Access-Control-Allow-Origin: https://www.example.com
   Access-Control-Allow-Methods: GET, POST, PUT, DELETE
   Access-Control-Allow-Headers: content-type, authorization
   Access-Control-Max-Age: 3600

3. 预检通过，浏览器才发真正的 POST 请求
```

**这意味着一次业务调用变成了两次网络往返**，所以 `Access-Control-Max-Age` 很重要 —— 它让浏览器缓存预检结果，有效期内同一接口不再重复预检。

### 响应头速查

| 响应头 | 作用 |
|--------|------|
| `Access-Control-Allow-Origin` | 允许哪个源，值为具体域名或 `*` |
| `Access-Control-Allow-Methods` | 允许的 HTTP 方法 |
| `Access-Control-Allow-Headers` | 允许携带的请求头 |
| `Access-Control-Allow-Credentials` | 是否允许携带 Cookie |
| `Access-Control-Max-Age` | 预检结果缓存秒数 |
| `Access-Control-Expose-Headers` | **允许前端 JS 读取的响应头**，不配则读不到自定义头 |

## 生产中的解决方案

### 方案选型

| 方案 | 适用环境 | 推荐度 |
|------|----------|--------|
| **同域部署（Nginx 反向代理）** | 生产 | 首选 |
| **网关/Nginx 统一配 CORS** | 生产，前后端必须分离部署 | 推荐 |
| **后端框架配置 CORS** | 生产，无独立网关时 | 常用 |
| **前端开发代理** | 仅本地开发 | 开发专用 |
| JSONP | — | 已淘汰，只支持 GET 且有安全问题 |

### 方案一：同域部署（生产首选）

**生产环境最好的跨域方案是「不跨域」。** 用 Nginx 把前端静态资源和后端接口挂在同一个域名下，用路径区分：

```nginx
server {
    listen 443 ssl;
    server_name www.example.com;

    # 前端静态资源
    location / {
        root /usr/share/nginx/html;
        try_files $uri $uri/ /index.html;   # 前端路由 history 模式必备
    }

    # 后端接口，同域名不同路径 —— 浏览器认为是同源
    location /api/ {
        proxy_pass http://backend-service:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

这样做的好处：

- 完全不触发 CORS，**没有预检请求的额外开销**
- Cookie 天然可用，不需要处理 `SameSite` 问题
- 后端代码里一行 CORS 配置都不用写

如果架构允许，优先选这个方案。

### 方案二：Nginx 统一配置 CORS

前后端确实分属不同域名时（比如 `www.example.com` 调 `api.example.com`），在网关层统一处理：

```nginx
location /api/ {
    # 不要用 *，明确指定允许的源
    add_header 'Access-Control-Allow-Origin' 'https://www.example.com' always;
    add_header 'Access-Control-Allow-Credentials' 'true' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'Content-Type, Authorization, X-Requested-With' always;
    add_header 'Access-Control-Max-Age' 3600 always;

    # 预检请求直接返回 204，不转发给后端，节省一次后端调用
    if ($request_method = 'OPTIONS') {
        return 204;
    }

    proxy_pass http://backend-service:8080/;
}
```

两个容易踩的点：

- **必须加 `always`**，否则 4xx/5xx 响应不会带上 CORS 头，前端看到的是跨域报错而不是真实的错误码
- **`if` 块里的 `add_header` 会失效**（Nginx 的已知行为），所以上面把 `add_header` 写在 `if` 外层

### 方案三：Spring Boot 后端配置

**全局配置（推荐）**

```java
@Configuration
public class CorsConfig implements WebMvcConfigurer {

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/**")
                // Spring Boot 2.4+ 用 allowedOriginPatterns，支持通配且能配合凭证
                .allowedOriginPatterns("https://*.example.com")
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
                .allowedHeaders("*")
                // 前端要读的自定义响应头必须显式暴露
                .exposedHeaders("X-Total-Count", "X-New-Token")
                .allowCredentials(true)
                .maxAge(3600);
    }
}
```

**局部注解**（只给个别接口开放时用）

```java
@CrossOrigin(origins = "https://www.example.com", maxAge = 3600)
@GetMapping("/public/config")
public ConfigDTO getConfig() { ... }
```

**Spring Security 环境下的必备配置**

这是生产中最高频的问题：配了 CORS 依然报跨域，实际原因是 `OPTIONS` 预检请求不带 Token，被 Security 拦下返回 401，浏览器就报成了跨域错误。

```java
@Bean
public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http
        // 关键：让 Security 感知 CORS 配置，CorsFilter 会排在认证过滤器之前
        .cors(cors -> cors.configurationSource(corsConfigurationSource()))
        .csrf(csrf -> csrf.disable())
        .authorizeHttpRequests(auth -> auth
            // 显式放行所有预检请求
            .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
            .requestMatchers("/api/public/**").permitAll()
            .anyRequest().authenticated()
        );
    return http.build();
}

@Bean
public CorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration config = new CorsConfiguration();
    config.setAllowedOriginPatterns(List.of("https://*.example.com"));
    config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
    config.setAllowedHeaders(List.of("*"));
    config.setExposedHeaders(List.of("X-Total-Count"));
    config.setAllowCredentials(true);
    config.setMaxAge(3600L);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", config);
    return source;
}
```

### 方案四：本地开发代理

开发阶段前端跑在 `localhost:5173`，后端在 `localhost:8080`，用开发服务器代理绕过，**不要为了本地方便去改生产的 CORS 配置**。

```javascript
// vite.config.js
export default {
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,      // 修改请求头 Host 为目标地址
        rewrite: path => path.replace(/^\/api/, '')
      }
    }
  }
}
```

原理和 Nginx 反代一致：浏览器只和 `localhost:5173` 通信，由 Node 开发服务器转发到后端，服务端之间的转发不受同源策略约束。

## [进阶] 关键配置要点

### 通配符与凭证互斥

**`allowCredentials(true)` 时，`Access-Control-Allow-Origin` 不能是 `*`** —— 这是规范的硬性规定，否则任何网站都能带着用户 Cookie 调你的接口。

Spring Boot 2.4 之后遇到这种配置会直接启动失败并抛异常。解决办法是用 `allowedOriginPatterns` 代替 `allowedOrigins`：

```java
// 报错
.allowedOrigins("*").allowCredentials(true)

// 正确
.allowedOriginPatterns("https://*.example.com").allowCredentials(true)
```

生产环境本来也应该明确列出可信来源，不要图省事用 `*`。

### 前端读不到自定义响应头

跨域下 JS 默认只能读到 6 个基本响应头。要读分页总数、刷新后的 token 这类自定义头，**服务端必须用 `Access-Control-Expose-Headers` 显式暴露**：

```java
.exposedHeaders("X-Total-Count", "X-New-Token")
```

不配的话，前端 `response.headers.get('X-Total-Count')` 拿到的是 `null`，而且控制台没有任何报错，排查起来很费时间。

### 携带 Cookie 与 SameSite

跨域带 Cookie 需要三方同时满足：

```javascript
// 1. 前端显式开启
axios.defaults.withCredentials = true;
```

```java
// 2. 后端允许凭证
config.setAllowCredentials(true);
```

```
// 3. Cookie 本身必须放开 SameSite
Set-Cookie: token=xxx; SameSite=None; Secure; HttpOnly
```

Chrome 80 之后 Cookie 默认 `SameSite=Lax`，**跨站请求不会携带 Cookie**。要跨域携带就得设 `SameSite=None`，而它又强制要求 `Secure`（必须 HTTPS）。

> 正因为这套限制越来越严，现在主流做法是**改用 `Authorization: Bearer <token>` 请求头传递凭证**，彻底绕开 Cookie 的跨站限制。新项目建议直接走 Token 方案。

### 减少预检开销

预检让每次调用变成两次往返。优化手段：

- 设置 `Access-Control-Max-Age`（建议 3600 秒），缓存期内不再预检
- 注意 Chrome 对该值有上限，超过 **7200 秒**按 7200 处理
- 能同域部署就同域部署，从根上消除预检

## [进阶] 常见坑点

| 现象 | 原因与解决 |
|------|------------|
| 配了 CORS 仍报跨域 | Spring Security 拦截了 `OPTIONS`，需 `http.cors()` 并放行 OPTIONS |
| 报错 `Allow-Origin contains multiple values` | Nginx 和后端都配了 CORS，头被加了两次。**只在一处配置** |
| 接口报跨域，但数据其实已经写入 | 请求已到达服务器并执行，只是响应被浏览器拦截 |
| 401/500 时前端只看到跨域错误 | 错误响应未带 CORS 头。Nginx 加 `always`，Spring 检查全局异常处理器 |
| 前端读不到自定义响应头 | 未配置 `Access-Control-Expose-Headers` |
| 启动报 `allowCredentials true 与 * 冲突` | 改用 `allowedOriginPatterns` |
| 跨域后 Cookie 丢失 | 缺 `withCredentials`，或 Cookie 未设 `SameSite=None; Secure` |
| 本地开发正常，上线就跨域 | 本地走的是开发服务器代理，生产没有这层，需在 Nginx 或后端配置 |

## 参考资源

- [HTTP-连接管理](../../network/HTTP/notes.md) - HTTP 协议基础
- [SSE-服务器单向推送](../../network/SSE/notes.md) - SSE 跨域需配合 `withCredentials`
- [MDN - 跨源资源共享 CORS](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/CORS) - 最完整的中文说明
- [Fetch Standard - CORS protocol](https://fetch.spec.whatwg.org/#http-cors-protocol) - 规范原文
