现在我已经收集到足够的信息，可以开始生成详细的方法解释了。

## PayerController.kycInfo 方法解析

**业务术语表**：
- **KYC**: Know Your Customer，客户身份识别/实名认证，是金融合规要求
- **Payer**: 付款人/汇款人，指使用系统进行汇款的用户
- **合并KYC**: 将多个用户的KYC信息合并到一个主账号下
- **证件过期状态**: 用户证件临近或已过期，影响KYC有效性
- **大额汇款材料**: 超过一定金额的汇款需要额外提交的证明文件
- **GLN**: 推测为韩国市场的合作伙伴或业务渠道
- **STB**: Starry Blue，推测为会员体系或特殊用户标识

**方法概述**：
这是KYC信息查询的核心接口方法，用于获取用户的完整实名认证信息。支持多市场、缓存优化、合并账户、证件状态检测等复杂业务场景。

**相关上下文**：
```java
@Resource
private UserService userService;              // 用户基础信息服务
@Resource
private CommonMethod commonMethod;            // 加载对应国家的KYC服务
@Resource
private RedisService redisService;            // Redis缓存服务
@Resource
private AsyncPost asyncPost;                  // 异步任务处理
@Resource
private CommonConfigs commonConfigs;          // 通用配置（如缓存排除国家列表）
@Resource
private KycUserRelationMapper kycUserRelationMapper;  // KYC账户合并关系
@Resource
private AlipayService alipayService;          // 支付宝服务
@Resource
private LargeTransferService largeTransferService;    // 大额汇款服务
```

**代码逐行解释**：

```java
546     @PostMapping("info")  // HTTP POST接口，路径为 /v2/info
547     public ResultRich<PayerV2> kycInfo(@RequestBody PayerV2 payerParams) {  // 接收付款人查询参数，返回完整KYC信息
548 
549         logger.info("请求查询kyc信息，请求参数:{}", JSON.toJSONString(payerParams));
550         redisService.incr("KYC_QUERY_COUNT", 1L);  // 统计KYC查询次数（监控指标）
551 
552         if (payerParams.getId() != null && payerParams.getUserId() != null && payerParams.getUserId() != 0L && payerParams.getId() != 0L) {  // 兼容处理：id和userId字段统一
553             payerParams.setUserId(payerParams.getId());
554         }
555 
556         ResultRich<Users> result = userService.selectById(payerParams.getUserId());  // 查询用户基础信息
557         logger.info("查询User返回：{}, {}", JSON.toJSONString(result), payerParams.getUserId());
558 
559         if (result.isSuc() && result.getModel() != null) {  // 用户存在，继续处理
560             //韩国收款人分享查询信息不切换users市场
561             if (CountryEnum.Korea.getMsg().equals(payerParams.getPayeeShareCountry())) {  // 特殊场景：韩国收款人分享链接查询
562                 result.getModel().setCountryCode(CountryEnum.Korea.getMsg());  // 强制设置为韩国市场
563             }
564 
565             //查询缓存中是否有kyc信息
566             Object object = null;
567             if (StringUtils.isNotEmpty(payerParams.getCountryCode())) {  // 请求参数指定了国家
568                 object = redisService.get(String.format(BaseConst.KYC_INFO, payerParams.getCountryCode(), payerParams.getUserId()));  // 从缓存获取KYC信息
569             } else {  // 未指定国家，使用用户注册时的国家
570                 object = redisService.get(String.format(BaseConst.KYC_INFO, result.getModel().getCountryCode(), payerParams.getUserId()));
571             }
572 
573             Boolean excludeCountry = (StringUtils.isNotEmpty(payerParams.getCountryCode()) && commonConfigs.getExcludeKycCacheCountries().contains(payerParams.getCountryCode()))  // 判断是否为排除缓存的国家
574                     || (StringUtils.isNotEmpty(result.getModel().getCountryCode()) && commonConfigs.getExcludeKycCacheCountries().contains(result.getModel().getCountryCode()));
575 
576             if (object != null && !excludeCountry) {  // 缓存命中且非排除国家
577                 redisService.incr("KYC_CACHE_COUNT", 1L);  // 统计缓存命中次数
578                 logger.info("请求查询kyc信息，本次从缓存中获取");
579                 PayerV2 cacheObj = JSONObject.parseObject(object.toString(), PayerV2.class);  // 反序列化缓存对象
580                 logger.info("请求查询kyc信息，缓存获取结果:{}", JSON.toJSONString(cacheObj));
581                 //查询大额汇款材料状态
582                 initLargeStatus(cacheObj);  // 实时查询大额汇款材料审核状态
583                 cacheObj.setUserLabel(userService.getUserLabelByCountry(cacheObj));  // 设置用户标签（如VIP等）
584                 cacheObj.setStatus(result.getModel().getStatus());  // 更新用户状态（可能已变化）
585                 if (StringUtils.isEmpty(result.getModel().getPhoneNumber()) || !result.getModel().getPhoneNumber().contains("_D")) {  // 电话号码未被逻辑删除
586                     cacheObj.setUserPhoneNumber(result.getModel().getPhoneNumber());  // 更新最新手机号
587                     cacheObj.setUserAreaCode(result.getModel().getAreaCode());  // 更新最新区号
588                 }
589                 return ResultRich.newInstance(cacheObj);  // 返回缓存结果
590             }
591 
592             ResultRich<PayerV2> selectResult;  // 准备从数据库查询的结果
593             String userCountryCode = result.getModel().getCountryCode();  // 用户注册时的国家代码
594 
595             if (StringUtils.isEmpty(payerParams.getCountryCode())) {  // 请求未指定国家
596                 payerParams.setCountryCode(userCountryCode);  // 使用用户注册国家
597             }
598 
599             // 查询该用户是否合并过kyc信息
600             KycUserRelation kycUserRelation = kycUserRelationMapper.queryByUserInfo(payerParams.getUserId(), payerParams.getCountryCode());  // 检查账户合并关系
601             Long mergeUserId = null;
602             if (kycUserRelation != null) {  // 用户KYC已被合并到另一个主账号
603                 logger.info("此查询用户涉及合并kyc操作，kyc合并信息：{}", JSONObject.toJSONString(kycUserRelation));
604                 payerParams.setMergeUserId(kycUserRelation.getMergeUserId());  // 设置合并的主账号ID
605                 mergeUserId = kycUserRelation.getMergeUserId();
606             }
607 
608             BaseKycService kycService = commonMethod.loadService(payerParams);  // 根据国家代码加载对应的KYC服务（如澳洲、韩国、欧洲等）
609             if (kycService == null) {  // ⚠️ 异常处理：没有对应国家的KYC服务
610                 // 如果没有对应的KYC服务，则直接返回user信息
611                 selectResult = UserConvertPayerV2.toPayerV2Result(result);  // 将User对象转换为PayerV2对象
612                 logger.error("没有查询到对应国家[{}]到KYC服务，直接返回User对象", payerParams.getCountryCode());
613             } else {
614                 // 调用对应kyc服务的方法
615                 selectResult = kycService.queryPayerInfo(payerParams);  // 从具体国家的KYC库查询数据
616                 logger.info("selectResult:{}", JSONObject.toJSONString(selectResult));
617                 if (!selectResult.isSuc()) {  // ⚠️ 异常处理：查询失败直接返回
618                     return selectResult;
619                 }
620                 if (selectResult.isSuc() && selectResult.getModel() != null && selectResult.getModel().getCountryCode().equals(CountryEnum.China.getMsg())) {  // 中国市场特殊处理
621                     // 中国kyc设置user 开户状态为中国kyc状态
622                     result.getModel().setKycStatus(selectResult.getModel().getKycStatus());  // 同步KYC状态到User表
623                     if (StringUtils.isEmpty(selectResult.getModel().getPhoneNumber())) {  // 中国KYC无手机号时
624                         selectResult.setModel(null);  // 清空模型，后续按无KYC处理
625                     }
626                 }
627 
628                 if (selectResult.isSuc() && selectResult.getModel() == null) {  // 用户未做KYC
629                     //判断是否为注销状态
630                     if (result.getModel().getStatus().equals("DELETE")) {  // ⚠️ 异常处理：用户已注销
631                         return ResultRich.newInstance(ErrorCode.REMITTER_DETAIL_NOT_EXIST);
632                     }
633                     selectResult = UserConvertPayerV2.toPayerV2Result(result);  // 返回User基础信息
634                     //如果kyc没有信息则将姓名全部设置为空
635 //                    selectResult.getModel().setFirstName(null);  // 已注释：不再清空姓名
636 //                    selectResult.getModel().setLastName(null);
637                     if (CountryEnum.Korea.getMsg().equals(payerParams.getPayeeShareCountry())) {  // 韩国收款人分享场景
638                         //韩国收款人分享无kyc初始化数据直接返回
639                         selectResult.getModel().setCountryCode(payerParams.getPayeeShareCountry());
640                         selectResult.getModel().setKycStatus((byte) KYCStatusForShow.INIT.getCode());  // KYC状态设为初始化
641                         selectResult.getModel().setStatus(result.getModel().getStatus());
642                         return selectResult;
643                     }
644 
645                 } else if (selectResult.isSuc() && selectResult.getModel() != null && StringUtils.isBlank(selectResult.getModel().getAreaCode())  // KYC有数据但区号为空
646                         && result.getCode() == 0 && result.getModel() != null) {
647                     //处理areaCode为空问题
648                     selectResult.getModel().setAreaCode(result.getModel().getAreaCode());  // 从User表补充区号
649                 }
650 
651                 //查询用户是否重复开户
652                 this.judgeIsRepeatOpenAccount(selectResult.getModel());  // 检测重复开户（风控）
653             }
654 
655             //同步kyc表和user表kyc状态
656             asyncPost.syncKycStatus(result.getModel(), selectResult.getModel());  // 异步同步KYC状态到User表
657 
658             //查询用户kyc打回信息
659             if (selectResult.getModel().getKycStatus() != 0 && selectResult.getModel().getRepeatUserInfo() == null) {  // 非初始状态且非重复账户
660                 // 判断是否为合并kyc
661                 if (mergeUserId != null) {  // 账户已合并
662                     logger.info("合并kyc查询用户kyc打回信息,[{}]", mergeUserId);
663                     selectResult.getModel().setMergeUserId(mergeUserId);
664                 }
665                 selectResult.getModel().setKycAudit(userService.getUsersKycAudit(selectResult.getModel()));  // 查询审核打回原因
666             }
667 
668             //查询用户kyc证件信息(日本和欧洲的证件依旧在jpkyc中获取) 再加新加坡
669             if (!selectResult.getModel().getCountryCode().equals(CountryEnum.Japan.getMsg()) && !CountryEnum.isEurCountry(selectResult.getModel().getCountryCode()) &&  // 排除日本、欧洲、新加坡
670                     !selectResult.getModel().getCountryCode().equals(CountryEnum.Singapore.getMsg()) && needDocListResp(selectResult.getModel())) {  // 需要返回证件列表
671                 selectResult.getModel().setImages(userService.getUsersDocs(payerParams.getUserId(), selectResult.getModel().getCountryCode()));  // 查询证件图片列表
672             }
673 
674 
675             // 查询微信昵称和头像
676             if (result.getModel().getWechatId() != null && result.getModel().getWechatId() > 0) {  // 用户绑定了微信
677                 WechatUserInfo wechatInfo = userService.selectWechatInfoById(result.getModel().getWechatId());
678                 if (wechatInfo != null) {
679                     selectResult.getModel().setNickName(wechatInfo.getNickName());  // 设置微信昵称
680                     selectResult.getModel().setAvatar(wechatInfo.getAvatar());  // 设置微信头像
681                 }
682             }
683 
684             // 是否需要完善密码
685             if (selectResult.isSuc()) {
686                 //韩国重置密码
687                 selectResult.getModel().setClauseStatus(result.getModel().getClauseStatus());  // 设置条款状态
688                 selectResult.getModel().setHasPassword(StringUtils.isNotEmpty(result.getModel().getPassword()));  // 是否已设置登录密码
689 
690                 //澳大利亚/新加坡/美国/加拿大
691                 //v2 放开限制
692                 try {
693                     //是否设置过密码 和 重置过密码
694                     PayPwdInfoVO payPwdInfoVO = userService.judgePwdInfo(result.getModel().getId());  // 查询支付密码状态
695                     logger.info("查询支付密码情况:{}", JSONObject.toJSONString(payPwdInfoVO));
696                     if (payPwdInfoVO != null) {
697                         selectResult.getModel().setHasPayPassword(payPwdInfoVO.getHasPayPassword());  // 是否已设置支付密码
698                         selectResult.getModel().setHasResetPayPwd(payPwdInfoVO.getHasResetPayPwd());  // 是否已重置过支付密码
699                     }
700                 } catch (Exception e) {  // ⚠️ 异常处理：支付密码查询异常不影响主流程
701                     logger.error("查询支付密码情况异常", e);
702                 }
703                 // 字段解密
704                 this.setKycDecryptedFields(selectResult.getModel());  // 解密敏感字段（如身份证号）
705             }
706 
707             if (CountryEnum.Korea.getMsg().equals(selectResult.getModel().getCountryCode())) {  // 韩国市场特殊处理
708                 initKoreaGlnUserVersion(selectResult.getModel(), payerParams);  // 初始化韩国GLN用户版本和渠道
709                 selectResult.getModel().setIdNumber(StringOffsetUtil.addAsciiRightMove(selectResult.getModel().getIdNumber(), 50));  // 身份证号加密偏移
710                 selectResult.getModel().setBankRegNumber(StringOffsetUtil.addAsciiRightMove(selectResult.getModel().getBankRegNumber(), 50));  // 银行注册号加密偏移
711             }
712 
713             // 香港 sex  字段 特殊处理
714             if (CountryEnum.HongKong.getMsg().equals(selectResult.getModel().getCountryCode())) {  // 香港市场特殊处理
715                 handleSex(result, selectResult);  // 性别字段按语言转换（男/女、M/F、male/female）
716             }
717 
718             //判断更新证件状态
719             if (selectResult.getModel() != null && selectResult.getModel().getTimeRemaining4Expire() != null && selectResult.getModel().getKycStatus().intValue() == 1) {  // KYC已通过且证件有过期时间
720                 if (userCountryCode.equals(CountryEnum.Australia.getMsg())  // 澳大利亚、新西兰、香港、美国、加拿大、巴西、墨西哥需要检测证件过期
721                         || userCountryCode.equals(CountryEnum.NewZealand.getMsg())
722                         || userCountryCode.equals(CountryEnum.HongKong.getMsg())
723                         || userCountryCode.equals(CountryEnum.America.getMsg())
724                         || userCountryCode.equals(CountryEnum.Canada.getMsg())
725                         || userCountryCode.equals(CountryEnum.Brazil.getMsg())
726                         || userCountryCode.equals(CountryEnum.Mexico.getMsg())) {
727                     selectResult.getModel().setIdentityStatus(asyncPost.updateIdentityStatus(selectResult.getModel()));  // 更新证件过期状态
728                     if (selectResult.getModel().getIdentityStatus() != null && (selectResult.getModel().getIdentityStatus() == 1 || selectResult.getModel().getIdentityStatus() == 2)) {  // 证件已过期或即将过期
729                         asyncPost.addKycAudit4DocExpire(selectResult.getModel());  // 创建证件过期的打回记录
730                     }
731                 }
732             }
733 
734             //判断用户是否为支付宝小程序查询注册支付宝相关会员
735             if (payerParams.getRequestSource() != null && payerParams.getRequestSource() == 8 && selectResult.getModel() != null && selectResult.getModel().getKycStatus().intValue() != 0) {  // 支付宝小程序来源且已做KYC
736                 AlipayUsersInfo alipayUsersInfo = alipayService.selectByUserId(payerParams.getUserId());
737                 if (alipayUsersInfo != null) {
738                     //判断用户是否为小程序提交订单且是否注册支付宝相关会员
739                     if (StringUtils.isNotEmpty(alipayUsersInfo.getMemberId()) && StringUtils.isEmpty(alipayUsersInfo.getTransferMemberId())) {  // 已注册支付宝会员但未注册转账会员
740                         asyncPost.registerAlipayTransferMember(selectResult.getModel(), alipayUsersInfo);  // 异步注册支付宝转账会员
741                     }
742                 }
743             }
744 
745             if (selectResult.getModel() != null) {
746                 selectResult.getModel().setUserLanguage(payerParams.getUserLanguage() == null ? result.getModel().getUsingLanguage() : payerParams.getUserLanguage());  // 设置用户语言
747                 userService.putEnum2Payer(selectResult.getModel());  // 设置枚举字段的显示值
748                 userService.initKycPopInfo(selectResult.getModel());  // 初始化KYC弹窗信息
749             }
750 
751             // 查询游轮公司信息
752             if (selectResult.getModel() != null && StringUtils.isNotEmpty(selectResult.getModel().getCompany())) {  // 用户关联了游轮公司（留学生场景）
753                 CruiseCompanyDTO cruiseCompanyDTO = userService.cruiseCompanyByName(selectResult.getModel());
754                 selectResult.getModel().setCruiseCompanyDTO(cruiseCompanyDTO);  // 设置游轮公司详细信息
755             }
756 
757             // 初始化用户标签信息
758             if (selectResult.getModel() != null) {
759                 selectResult.getModel().setUserLabel(userService.getUserLabelByCountry(selectResult.getModel()));  // 设置用户标签（如VIP、新用户等）
760             }
761 
762             // 判断是否是开启了预约，是否该用户需要预约
763             String largeReserveCountryCode = CountryEnum.isEUCountryNoGBR(userCountryCode) ? CountryEnum.Europe.getMsg() : userCountryCode;  // 欧盟国家（除英国）统一为欧洲代码
764             if (commonConfigs.getLargeReserveCountries().contains(largeReserveCountryCode)) {  // 该国家开启了留学预约功能
765                 logger.info("进入留学预约页面:{}", userCountryCode);
766                 //if (userService.checkNeedInvite(selectResult.getModel().getUserId())) {  // 已注释：不再检查是否需要邀请
767                     //logger.info("封装留学预约参数：{}", selectResult.getModel().getUserId());
768                     selectResult.getModel().setIsReserved(userService.inviteCode(selectResult.getModel().getUserId()));  // 查询预约状态
769                 //}
770             } else {
771                 selectResult.getModel().setIsReserved(3);  // 未开启预约功能，设置为不需要预约
772             }
773 
774             //查询大额汇款材料状态
775             initLargeStatus(selectResult.getModel());  // 查询大额汇款材料审核状态（见前文）
776 
777             // 内部使用的countryCode字段，自users表的数据插入
778             // 加一层判断，非汇出kyc走下述逻辑
779             if (!CountryEnum.China.getMsg().equals(selectResult.getModel().getCountryCode())) {  // 非中国汇出市场
780                 selectResult.getModel().setCountryCode(userCountryCode);  // 使用用户注册时的国家代码
781             }
782             selectResult.getModel().setRemitFlag(result.getModel().getRemitFlag().intValue());  // 设置汇款标识
783             if (result.getModel() != null && result.getModel().getChannel() != null) {
784                 selectResult.getModel().setChannel(result.getModel().getChannel());  // 设置用户渠道
785             }
786 
787 //            try {  // 已注释：GLC gToken查询逻辑
788 //                Users query = new Users();
789 //                query.setId(payerParams.getUserId());
790 //                query.setCountryCode(payerParams.getCountryCode());
791 //                ResultRich<GlobalUser> globalUser = glcCoreClient.queryGtokenByUser(query);
792 //                if (globalUser.isSuc() && globalUser.getModel() != null) {
793 //                    logger.info("查询用户GLC获取结果gotken：{}", globalUser.getModel().getgToken());
794 //                    selectResult.getModel().setgToken(globalUser.getModel().getgToken());
795 //                }
796 //            } catch (Exception e) {
797 //                logger.info("查询用户gtoken异常", e);
798 //
799 //            }
800             if (StringUtils.isEmpty(selectResult.getModel().getgToken())) {  // gToken为空
801                 selectResult.getModel().setgToken(userService.selectGtokenByUserId(payerParams));  // 从数据库查询gToken
802             }
803 
804             if (selectResult.sucWithModel()  // 查询成功且有数据
805                     && result.sucWithModel()) {
806                 selectResult.getModel().setStatus(result.getModel().getStatus());  // 设置用户状态（DELETE/NORMAL等）
807                 selectResult.getModel().setUserEmail((result.getModel()).getEmail() != null ? (result.getModel()).getEmail() : "");  // 设置用户邮箱
808                 if (StringUtils.isEmpty(result.getModel().getPhoneNumber()) || !result.getModel().getPhoneNumber().contains("_D")) {  // 电话号码未被逻辑删除
809                     selectResult.getModel().setUserPhoneNumber(result.getModel().getPhoneNumber());  // 设置用户手机号
810                     selectResult.getModel().setUserAreaCode(result.getModel().getAreaCode());  // 设置用户区号
811                 }
812             }
813             if (selectResult.getModel() != null) {
814                 selectResult.getModel().setStbFlag(0);  // 默认非STB用户
815             }
816             judgeIsStbUser(selectResult);  // 判断是否为STB会员用户
817             judgeIsRemitUser(selectResult);  // 判断是否为汇出用户
818             setStbLevel(selectResult);  // 设置STB会员等级
819             //setStbToken(selectResult, payerParams.getRequestSource());  // 已注释：设置STB Token
820             logger.info("kyc_info:{}", JSONObject.toJSONString(selectResult));
821             return selectResult;  // 返回最终的KYC信息
822         } else {
823             return ResultRich.newInstance(ErrorCode.PAYER_INFO_QUERY_ERROR);  // ⚠️ 异常处理：用户不存在
824         }
825     }
```

**复杂逻辑详解**：

- **第 573-574 行**（复杂条件判断拆解）：
  1. `StringUtils.isNotEmpty(payerParams.getCountryCode())` - 请求参数指定了国家
  2. `commonConfigs.getExcludeKycCacheCountries().contains(...)` - 该国家在排除缓存列表中
  3. 或运算：请求国家或用户注册国家任一在排除列表，则不使用缓存

- **第 568-571 行**（缓存键构建逻辑）：
  - 优先使用请求参数中的国家代码
  - 若未指定，使用用户注册时的国家代码
  - 缓存键格式：`BaseConst.KYC_INFO + 国家代码 + 用户ID`

- **第 720-726 行**（多国家条件判断）：
  - 只有特定国家需要检测证件过期
  - 这些国家的监管要求需要定期更新证件信息

**被调用的业务方法**：
1. userService.selectById() - 查询用户基础信息
2. kycUserRelationMapper.queryByUserInfo() - 查询KYC账户合并关系
3. commonMethod.loadService() - 加载对应国家的KYC服务
4. kycService.queryPayerInfo() - 从国家KYC库查询数据
5. judgeIsRepeatOpenAccount() - 检测重复开户（风控）
6. asyncPost.syncKycStatus() - 异步同步KYC状态
7. userService.getUsersKycAudit() - 查询审核打回原因
8. userService.getUsersDocs() - 查询证件图片列表
9. userService.selectWechatInfoById() - 查询微信用户信息
10. userService.judgePwdInfo() - 查询支付密码状态
11. setKycDecryptedFields() - 解密敏感字段
12. initKoreaGlnUserVersion() - 初始化韩国GLN用户版本
13. handleSex() - 性别字段按语言转换
14. asyncPost.updateIdentityStatus() - 更新证件过期状态
15. asyncPost.addKycAudit4DocExpire() - 创建证件过期打回记录
16. asyncPost.registerAlipayTransferMember() - 注册支付宝转账会员
17. userService.putEnum2Payer() - 设置枚举显示值
18. userService.initKycPopInfo() - 初始化KYC弹窗信息
19. userService.cruiseCompanyByName() - 查询游轮公司信息
20. userService.getUserLabelByCountry() - 设置用户标签
21. userService.inviteCode() - 查询留学预约状态
22. initLargeStatus() - 查询大额汇款材料状态
23. userService.selectGtokenByUserId() - 查询gToken
24. judgeIsStbUser() - 判断是否为STB会员
25. judgeIsRemitUser() - 判断是否为汇出用户
26. setStbLevel() - 设置STB会员等级

需要深入解释哪些方法？（输入方法名或序号，或"无"结束）