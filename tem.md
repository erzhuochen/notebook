# nacos中的短信配置 迁移到数据库存取
需求描述

背景:由于系统经常遭受到各地的短信攻击请求，开发人员 经常要根据情况 对配置做出调整 由于nacos调整不便，统一整理到数据库，并由管理台管理数据。

1.短信条数拦截配置从nacos迁移到管理台（消息中心目录下）可配置 ，管理台新增修改刷新缓存  
2.wt-notification项目中发送短信之前会校验每小时和每天的条数拦截，可以改成直接读取KEY + 区号的缓存条数进行判断

以下为当前配置调用代码:
```java
private Integer queryAreaDayLimit(String areaCode) {  
    JSONObject limitJson = JSONObject.parseObject(smsConfig.getOptLimitJson());  
    if (limitJson.containsKey(areaCode)) {  
        return limitJson.getInteger(areaCode);  
    } else {  
        return smsConfig.getOptLimit();  
    }  
}  
  
private Integer queryAreaHourLimit(String areaCode) {  
    JSONObject limitJson = JSONObject.parseObject(smsConfig.getHourOptLimitJson());  
    if (limitJson.containsKey(areaCode)) {  
        return limitJson.getInteger(areaCode);  
    } else {  
        return smsConfig.getHourOptLimit();  
    }  
}
```