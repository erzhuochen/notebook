```java
public static String generateToken(String content) throws Exception {  
    String key = generateRandomKey(32);  
    String hmacKey = generateRandomKey(32);  
    String nonce = generateRandomKey(8);  
  
    String xorKey = calcXorKey(key);  
    String xorhmacKey = calcXorKey(hmacKey);  
    String xornonce = calcXorKey(nonce);  
  
    //encrypt  
    String b64encryptResult = AesUtil.aesEncrypt(content, key, nonce);  
  
    //signature  
    byte[] sha256Sign = SignatureUtil.encodeHmacSHA256(b64encryptResult.getBytes(), hmacKey.getBytes());  
    String b64Sha256Sign = Base64.encodeBase64String(sha256Sign);  
  
  
    String b64xorKey = Base64.encodeBase64String(xorKey.getBytes());  
    String b64xorhmacKey = Base64.encodeBase64String(xorhmacKey.getBytes());  
    String b64xornonce = Base64.encodeBase64String(xornonce.getBytes());  
  
    return String.format("%s#%s#%s#%s#%s", b64xorKey, b64xorhmacKey, b64xornonce, b64encryptResult, b64Sha256Sign);  
}
```


**可以把 token 理解成一张“装在加密信封里的登录证明”：AES 负责隐藏里面的用户信息，HMAC 负责检查密文是否被修改，nonce 负责让加密过程每次使用不同的起点。**

先记住它们的区别：

|名称|通俗理解|实际用途|
|---|---|---|
|AES 密钥|锁住信封、打开信封的钥匙|把用户信息变成密文，再把密文还原|
|HMAC 密钥|制作和核对防伪标记的钥匙|计算校验值，检查收到的密文是否被修改|
|nonce|每次加密使用的随机起点|参与初始化加密，使相同内容在相同密钥下也可以得到不同密文|

下面用测试账号 A 举例。只展示示意内容，不生成真实 token。

**第一步：准备登录证明里的内容**

A 登录成功后，工具类从登录结果里取出：

```
用户ID=A
KYC状态=……
环境=……
市场=……
语言=……
生成时间=……
```

这些信息目前是可以直接阅读的“明文”。组装位置是 [TokenInputUtil.java (line 211)](/D:/workspace/wh/wt/wt-core/src/main/java/com/wotransfer/core/token/TokenInputUtil.java:211)。

**第二步：用 AES 把内容锁起来**

可以理解为：

```
用户信息 + AES密钥 + nonce → 密文
```

以后服务器收到这个 token，再使用对应的密钥和 nonce，把密文还原成用户信息。

这就是“对称加密”：加密和解密使用同一把密钥。调用位置是 [TokenManagerUtil.java (line 108)](/D:/workspace/wh/wt/wt-core/src/main/java/com/wotransfer/core/token/TokenManagerUtil.java:108)。

这里需要细化上一条回答：代码中随机生成的 32 字符 `key`，实际是**生成 AES 密钥的种子**。底层工具根据它生成 **128 位 AES 密钥**，所以不能因为字符串长 32 个字符，就认为使用了 AES-256。见 [AesUtil.java (line 71)](/D:/workspace/wh/wt/wt-core/src/main/java/com/wotransfer/core/secure/AesUtil.java:71)。

**第三步：nonce 给加密设置一个起点**

假设相同用户信息、相同密钥每次都生成相同密文，外部就可能通过比较密文发现内容重复。(当前代码的密钥每次都是随机生成的)

nonce 的作用是让加密每次换一个起点。它参与加密，解密时也需要同一个值；通常不需要保密。

本项目生成 8 字符 nonce，然后与 8 个固定字节拼成 16 字节的初始化向量，也就是代码中的 `IV`：

```
nonce → 拼成 IV → 用于初始化 AES 加密
```

见 [AesUtil.java (line 54)](/D:/workspace/wh/wt/wt-core/src/main/java/com/wotransfer/core/secure/AesUtil.java:54) 和 [78 行 (line 78)](/D:/workspace/wh/wt/wt-core/src/main/java/com/wotransfer/core/secure/AesUtil.java:78)。

**nonce 本身不判断 token 是否过期，也不阻止别人重复提交同一个 token。**

**第四步：用 HMAC 给密文做防伪校验**

把它理解成一个由秘密钥匙计算出来的“指纹”：

```
密文 + HMAC密钥 → 校验值
```

服务器收到 token 后，再计算一次：

```
收到的密文 + 恢复出的HMAC密钥 → 新校验值
```

两个校验值一致，才继续解密。若有人改了密文，却没有对应密钥，就无法为修改后的密文计算正确的校验值。

**HMAC 不负责解密，也不能从校验值还原用户信息。** 它负责完整性校验，这一作用依赖 HMAC 密钥受到保护。生成位置是 [TokenManagerUtil.java (line 111)](/D:/workspace/wh/wt/wt-core/src/main/java/com/wotransfer/core/token/TokenManagerUtil.java:111)。

**第五步：把这些材料一起打包成 token**

本项目最终返回的结构是：

```
处理后的AES种子
# 处理后的HMAC密钥
# 处理后的nonce
# 密文
# HMAC校验值
```

前三项使用固定 `MASTER_KEY` 做可逆 XOR 变换，再进行 Base64 编码。这样服务器收到 token 后，可以恢复它们，完成校验和解密。

Base64 只是把数据转换成便于传输的字符串，保密能力来自其他步骤。打包位置是 [TokenManagerUtil.java (line 103)](/D:/workspace/wh/wt/wt-core/src/main/java/com/wotransfer/core/token/TokenManagerUtil.java:103) 和 [119 行 (line 119)](/D:/workspace/wh/wt/wt-core/src/main/java/com/wotransfer/core/token/TokenManagerUtil.java:119)。

**服务器收到 token 时，按相反顺序处理**

```
拆出五部分
 → 恢复HMAC密钥
 → 核对密文的校验值
 → 校验通过后恢复AES种子和nonce
 → 解密得到用户ID、市场等信息
```

解析入口是 [parseTokenStr():123 (line 123)](/D:/workspace/wh/wt/wt-core/src/main/java/com/wotransfer/core/token/TokenManagerUtil.java:123)。

结合你的越权审查：即使这些步骤证明 token 中的登录身份是 A，业务代码仍须检查请求里的 `gToken` 或目标账号是否属于 A。加密和完整性校验不会自动完成这个资源授权判断。
