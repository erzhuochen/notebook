## 请求头和响应头

浏览器发送的请求头：

|请求头|作用|示例／出现时机|
|---|---|---|
|`Origin`|标明发起请求的网页来源，包含协议、主机和端口|`https://app.example.com`|
|`Access-Control-Request-Method`|询问正式请求能否使用某个 HTTP 方法|`POST`；仅预检请求|
|`Access-Control-Request-Headers`|询问正式请求能否携带这些请求头|`content-type,token`；仅预检请求|
|`Content-Type`|声明请求体的格式；`application/json` 会触发跨域预检|`application/json`|
|`token`／`Authorization`|携带业务认证信息，会触发跨域预检|正式请求；服务器仍需验证其值|
|`Cookie`|浏览器携带接口域名对应的 Cookie，例如登录会话|正式请求；受凭据模式和 Cookie 规则控制|

服务器返回的响应头：

|响应头|作用|示例|
|---|---|---|
|`Access-Control-Allow-Origin`|允许哪个网页来源读取响应|`https://app.example.com` 或 `*`|
|`Access-Control-Allow-Methods`|告诉浏览器正式请求允许使用哪些方法|`GET, POST`；用于预检响应|
|`Access-Control-Allow-Headers`|告诉浏览器正式请求允许携带哪些请求头|`Content-Type, token`；用于预检响应|
|`Access-Control-Allow-Credentials`|允许凭据模式的跨域响应向网页开放|`true`|
|`Access-Control-Expose-Headers`|允许网页 JavaScript 读取默认范围之外的响应头|`X-Request-Id, Content-Disposition`|
|`Access-Control-Max-Age`|预检结果可以缓存多少秒，减少重复预检|`1800`；实际受浏览器上限限制|
|`Vary`|告诉缓存按指定请求头区分响应；动态返回不同允许来源时应包含 `Origin`|`Origin`|