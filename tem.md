# 数据库同步

在 ”D:\workspace\wh\manager\manager-data\src\main\java\com\wotransfer\dataManagement\config\DataSourceConfig.java“ 中通过"D:\workspace\wh\manager\manager-data\src\main\java\com\wotransfer\dataManagement\intercept\MybatisInterceptor.java"拦截sql请求，并通过”pmmClient.syncManagerSql(sqlSyncDTO);” 向其他的服务器发送相同的sql语句去同步数据库。
模仿它的形式，在“D:\workspace\wh\manager\manager-data\src\main\java\com\wotransfer\dataManagement\config\DataSourceConfigWallet.java”中配置拦截器