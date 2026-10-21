核心思路是：不要把参数拼进 SQL 字符串再传输，而是把 SQL 模板和参数分开传，在接收端用 `PreparedStatement` 执行。

## 现在的问题在哪里

`showSql` 把 `?` 用参数值做字符串替换，得到一个完整的 SQL 字符串，然后发出去，接收端用 `JdbcTemplate.update(sql)` 直接执行。这中间没有任何转义，`#{}` 原有的保护在这里完全失效。

## 安全的传输方式

**把 SQL 模板和参数列表分开传**

`BoundSql` 里本来就有这两样东西：

- `boundSql.getSql()`：带 `?` 的参数化模板（这个本身是安全的，由 MyBatis 生成，不含用户输入）
- `parameterMappings` + `parameterObject`：参数列表

把它们分别放进 DTO：

```java
// SqlSyncDTO 增加一个字段
private List<Object> params;  // 按顺序的参数值列表，不要做字符串拼接
```

拦截器里改为提取参数列表而不是拼接 SQL：

```java
private static List<Object> extractParams(Configuration configuration, BoundSql boundSql) {
    List<Object> result = new ArrayList<>();
    List<ParameterMapping> mappings = boundSql.getParameterMappings();
    Object paramObject = boundSql.getParameterObject();
    if (mappings == null || paramObject == null) return result;
    TypeHandlerRegistry registry = configuration.getTypeHandlerRegistry();
    if (registry.hasTypeHandler(paramObject.getClass())) {
        result.add(paramObject);
    } else {
        MetaObject meta = configuration.newMetaObject(paramObject);
        for (ParameterMapping mapping : mappings) {
            String prop = mapping.getProperty();
            if (meta.hasGetter(prop)) {
                result.add(meta.getValue(prop));
            } else if (boundSql.hasAdditionalParameter(prop)) {
                result.add(boundSql.getAdditionalParameter(prop));
            } else {
                result.add(null);
            }
        }
    }
    return result;
}
```

接收端改用带参数绑定的重载：

```java
// JdbcTemplate 接受 Object[] 参数，内部走 PreparedStatement
jdbcTemplate.update(sqlSyncDTO.getSql(), sqlSyncDTO.getParams().toArray());
```

这样接收端执行的是 `PreparedStatement`，JDBC 驱动负责转义，注入就被堵住了。

## 为什么这样才安全

`JdbcTemplate.update(String sql, Object... args)` 内部会创建 `PreparedStatement`，把参数通过 `setObject` 绑定，这和 MyBatis 处理 `#{}` 的机制是一样的——参数值永远不会拼进 SQL 文本。

同步链路就变成了：SG 把带 `?` 的模板 + 参数列表发出去 → PMM 透传 → 接收端用 `PreparedStatement` 执行。全程 SQL 结构不变，参数值不可能逃出绑定的边界。

## 顺带的好处

现在的 `showSql` 还有一个副作用：日志里打印的是参数替换后的完整 SQL，包含真实的业务数据（金额、用户 ID 等）。如果改成模板 + 参数分离的方式，可以只在日志里打模板，参数列表单独打或者只打类型，减少敏感数据暴露。

## 当前代码不用改的前提

如果这张表的所有写操作，入参来自纯内部逻辑（不含任何外部用户的文字输入），攻击面很小，风险可接受。一旦有表的某个字段是用户填写的内容，比如备注、名称、地址，就应该改成参数化传输。