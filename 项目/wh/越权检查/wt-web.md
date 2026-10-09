## 扩展：http请求的结构组成
这里的 **“请求属性（attribute）”是服务端给当前请求附加的数据**。`tokenObj` 是项目约定的名称，通过 `setAttribute()` 创建，不需要提前声明字段。

我找到了一个明确的赋值位置：依赖包 `com.wotransfer.core.token.TokenInputUtil` 的 **`convert2Token()`** 方法。它构造 `TokenInput` 后，执行的关键步骤相当于：

```
request.setAttribute("tokenObj", tokenInput);
```

后续代码就可以读取：

```
TokenInput tokenInput =
    (TokenInput) request.getAttribute("tokenObj");
```


**属性只在当前请求处理期间使用。** 登录请求设置的属性，不会自动保留到下一次资料更新请求中；跨服务发送新的 HTTP 请求时，也不会自动携带这些属性。

一个 HTTP 请求可以用下面的示意报文理解：

```
POST /user/update?source=app HTTP/1.1
Host: example.com
Content-Type: application/json
token: <登录凭据>
Cookie: sessionId=<会话标识>

{"id":1001,"cnFullName":"测试用户"}
```

它由**请求行、请求头、空行、请求体**组成：

|部分|示例|Java / Spring 中的读取方式|
|---|---|---|
|请求方法|`POST`|`request.getMethod()`，或通过映射限定|
|请求路径|`/user/update`|`request.getRequestURI()`、`@RequestMapping`|
|URL 查询参数|`source=app`|`@RequestParam`、`request.getParameter()`|
|请求头|`Content-Type`、`token`|`request.getHeader("token")`|
|Cookie|`sessionId=...`|`request.getCookies()`；它在报文中属于请求头|
|请求体|JSON 中的 `id`、`cnFullName`|`@RequestBody Users users`|
|服务端请求属性|内存中的 `TokenInput` 对象|`request.getAttribute("tokenObj")`|

最后一行是服务端请求对象附加的内容，**不会出现在上面的 HTTP 报文中**。JSON 请求体中的字段，也不会自动变成请求属性。

结合你的项目，三个容易混淆的读取操作分别是：

```
request.getHeader("token");        // HTTP 请求头中的登录凭据
request.getHeader("tokenObj");     // HTTP 请求头中的字符串
request.getAttribute("tokenObj");  // 服务端附加的 Java 对象
```

本机 `core` 依赖中的 `getTokenInputObj()` 逻辑相当于：

```
// 先读服务端请求属性
Object obj = request.getAttribute("tokenObj");
if (obj != null) {
    return (TokenInput) obj;
}

// 没有属性时，再尝试读取同名请求头并解析
String json = request.getHeader("tokenObj");
// 将 json 解析成 TokenInput；没有可用内容则返回 null
```

所以，**读取请求属性和读取请求头是两个不同的数据来源**。检查越权时，还要追踪当前接口调用前是谁填入了 `tokenObj`，尤其要确认同名请求头经过可信网关处理，而不是直接相信客户端提供的身份。