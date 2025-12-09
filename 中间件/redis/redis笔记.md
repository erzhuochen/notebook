# 1. command

## 1.1 String

<img src="assets/b4238053105541d99c1d784333427c88tplv-k3u1fbpfcp-jj-mark2268000q75.webp" alt="image.png" style="zoom:50%;" />

### 1.1.1 SET

`SET name 123 EX 20`

- `EX`: 设置一个过期时间, 时间单位秒
- `PX`: 类似, 时间单位毫秒
- `EXAT`和`PXAT`: 指定key在某个时间点过期
- `NX`: 目标Key不存在时, 才写入这个Key
- `XX`: Key存在时, 才写入这个Key

`SETNX` = `SET` + `NX`

`MSET`: SET的批量版本

`MSETNX`: `MSET` + `NX`

### 1.1.2 GET

`GET`

`MGET`

`GETEX`: 获取Key的值, 同时给Key设置一个过期时间

### 1.1.3 递增操作

`INCR age`

`INCR`: +1

`DECR`: -1

`INCRBY fans 100`: +100

`DECRBY fans 100`: -100



### 1.1.4 操作部分字符串

`APPEND`: 往一个Key里面追加一个字符串

`GETRANGE`: 类似`subsring()`, 但它是闭区间

<img src="assets/155da43c1ec24acda49fccb8ecd817e1tplv-k3u1fbpfcp-jj-mark2268000q75.webp" alt="image.png" style="zoom: 50%;" />

`SETRANGE`: 指定一个下标, 替换这个下标后的内容

<img src="assets/71e8075501744614b8654551fc69e1d1tplv-k3u1fbpfcp-jj-mark2268000q75.webp" alt="image.png" style="zoom:50%;" />

### 1.1.5 复合操作

`GETSET`: 先get再set

`GETEX`: 获取Key的值, 同时给Key设置一个过期时间

`GETDEL`



## 1.2 List

![image.png](assets/21f2e572e3f54b869b20be1d38fccef2tplv-k3u1fbpfcp-jj-mark2268000q75.webp)

### 1.2.1 基础操作

`LPUSH`

`RPOP`: 可指定弹出几个, 例如 `RPOP testlist 2`, 弹出2个元素

`RPUSH`

`LPOP`

`LRANGE testlist 0 5`: 获得列表[0, 5]的元素

注意负数的下标规则

<img src="assets/29a6cb63fbca4b08a323b66790cf8c77tplv-k3u1fbpfcp-jj-mark2268000q75.webp" alt="image.png" style="zoom: 33%;" />

`LLEN testlist`: 查list中元素个数



### 1.2.2 阻塞操作

`BLPOP blist1 10`: 阻塞的超时时间为10秒

`BRPOP`

监听多个list:

```shell
127.0.0.1:6379> BLPOP blist1 blist2 blist3 10 # 新客户端
1) "blist3"
2) "BBB"
(8.00s)
127.0.0.1:6379> LPUSH blist3 BBB # 老客户端
(integer) 1
```



### 1.2.3 复合操作

`LMOVE`: 从一个List里面弹出元素, 同时把这个弹出元素重写写入到另一个List

```shell
127.0.0.1:6379> LPUSH movelist1 AAA BBB CCC DDD
(integer) 4
127.0.0.1:6379> LMOVE movelist1 movelist2 LEFT LEFT
"DDD"
127.0.0.1:6379> LRANGE movelist2 0 -1
1) "DDD"
```

`BLMOVE`: `LMOVE`的阻塞版本



### 1.2.4 随机访问

慢, 不建议用

`LINDEX`

```shell
127.0.0.1:6379> LPUSH indexlist AAA BBB CCC
(integer) 3
127.0.0.1:6379> LRANGE indexlist 0 -1
1) "CCC"
2) "BBB"
3) "AAA"
127.0.0.1:6379> LINDEX indexlist 1
"BBB"
127.0.0.1:6379> LINDEX indexlist 0
"CCC"
```

`LPOS`: 根据元素值查找对应下标, 默认返回第一个相等元素下标

- RANK: 返回第几个下标
- COUNT: 返回多少个下标索引值, `COUNT 0`返回所有下标索引
- MAXLEN: 指定一次LPOS命令最多比较多少次

`LINSERT`

```shell
127.0.0.1:6379> LINSERT indexlist AFTER BBB DDD
(integer) 4
127.0.0.1:6379> LRANGE indexlist 0 -1
1) "CCC"
2) "BBB"
3) "DDD"
4) "AAA"
```

`LSET`: 把指定索引的元素换掉. eg. LSET indexlist 2 DDD

`LREM indexlist 1 AAA`: 删除一个AAA字符串

- count: 是正数, 从左往右删; 0, 全部删; 负数, 从右往左删

`LTRIM`: 截断List

```shell
127.0.0.1:6379> DEL indexlist
(integer) 1
127.0.0.1:6379> RPUSH indexlist AAA BBB CCC AAA CCC CCC CCC
(integer) 7
127.0.0.1:6379> LTRIM indexlist 2 -1
OK
127.0.0.1:6379> LRANGE indexlist 0 -1
1) "CCC"
2) "AAA"
3) "CCC"
4) "CCC"
5) "CCC"
```



### 1.2.5 消息队列

但是，使用 Lettuce 这个客户端的时候，需要注意一个坑：正常情况下，像执行 LPUSH、SET、GET 这些非阻塞的命令，Lettuce 的 Connection 是可以在不同线程之间共享的，但是如果执行 BRPOP 这种阻塞命令，就不能共享 Connection 了。

两个线程共用了一个 Connection 去执行 BRPOP 这种阻塞命令，BRPOP 命令是在 Redis 服务端阻塞的，会和 Connection 本地的 get() 超时时间相互影响。

所以，要启动多个 Consumer 线程，比较简单的方式，**启动多个进程来执行 MQConsumerTest() 这个单元测试方法**就行了。如果要使用多线程的方式执行 MQTest2Consumer() 的逻辑，就需要为每个线程创建专属的 Connection 对象。



### 1.2.6 提醒功能

在有的场景里面，Redis List 可以用来存放提醒类的消息，这类消息不像订单之类的消息，提醒类的消息是`可以接受丢失`的。

和消息队列差不多, 本质上都是生产者消费者的模式, 感觉没啥用



### 1.2.7 热点新闻

没用



## 1.3 Hash

<img src="assets/aed9af96c59948599ddd775ba16e49fbtplv-k3u1fbpfcp-jj-mark2268000q75.webp" alt="image.png" style="zoom:50%;" />

### 1.3.1 读写操作

#### HSET, HSETNX

```shell
// HSET
127.0.0.1:6379> HSET testHash name kouzhaoxuejie
(integer) 1
127.0.0.1:6379> HSET testHash age 25 height 170
(integer) 2

// HSETNX
127.0.0.1:6379> HSETNX testHash name kouzhao
(integer) 0
127.0.0.1:6379> HGET testHash name
"kouzhaoxuejie"
127.0.0.1:6379> HSETNX testHash weight 100
(integer) 1
127.0.0.1:6379> HGET testHash weight
"100"
```

#### HGET, HMGET

```shell
127.0.0.1:6379> HGET testHash name
"kouzhaoxuejie"
127.0.0.1:6379> HMGET testHash name age height
1) "kouzhaoxuejie"
2) "25"
3) "170"
```



#### HEXISTS

```shell
127.0.0.1:6379> HEXISTS testHash name
(integer) 1 // testHash中, name存在
127.0.0.1:6379> HEXISTS testHash weight
(integer) 0 // weight不存在
```



#### HDEL

```shell
127.0.0.1:6379> HDEL testHash weight
(integer) 1
127.0.0.1:6379> HGET testHash weight
(nil)
```



### 1.3.2 递增操作

#### HINCRBY, HINCRBYFLOAT

```shell
// HINCRBY
127.0.0.1:6379> HSET testHash fans 100
(integer) 1
127.0.0.1:6379> HINCRBY testHash fans 2
(integer) 102

// HINCRBYFLOAT
127.0.0.1:6379> HSET testHash account 100
(integer) 1
127.0.0.1:6379> HGET testHash account
"100"
127.0.0.1:6379> HINCRBYFLOAT testHash account -50.5
"49.5"
127.0.0.1:6379> HGET testHash account
"49.5"
```



### 1.3.3 批量读取

#### HGETALL

获得哈希表中的所有field-value值

```shell
127.0.0.1:6379> HGETALL testHash
 1) "name"
 2) "kouzhaoxuejie"
 3) "age"
 4) "26"
 5) "height"
 6) "170"
 7) "fans"
 8) "102"
 9) "account"
10) "49.5"
```



#### HKEYS

只获取field值

```shell
127.0.0.1:6379> HKEYS testHash
1) "name"
2) "age"
3) "height"
4) "fans"
5) "account"
```



#### HVALS

```shell
127.0.0.1:6379> HVALS testHash
1) "kouzhaoxuejie"
2) "26"
3) "170"
4) "102"
5) "49.5"
```



#### HSCAN

把一次获取哈希表全量数据的这个操作, 拆成了多次迭代, 一次迭代只返回一部分数据

```shell
HSCAN key cursor [MATCH pattern] [COUNT count]
```

- key: 要扫描的哈希表的名称
- cursor: 游标. 告诉Redis从哪里开始下一次迭代
- MATCH: 类似SQL中的where条件, 按照一定的格式来过滤field
- COUNT: 类似SQL中的limit, 但只能提示Redis应该返回多少条数据, 不是严格控制

下面我们还是通过一个示例来说明 HSCAN 命令的具体使用方式。在下面的 testClass 这个哈希表里面，有 1000 个学生的指纹信息，这里随机抽几个学生的指纹信息看一眼，student1、student2 这两个学生的指纹信息是加密的编码；之后，用 HLEN 命令来看一下 testClass 里面有多少条指纹信息，总共 1000 个。

```shell
127.0.0.1:6379> HMGET testClass student1 student2
1) "wIBWRf4hDR8S1ZoHjR7FfdCDugOXPuZOujiVaUMUZPUs9iTgqI3B42Dq3YIUD3VaVExK4cSXYKhS4BxDMrvmlXIhg67vTMdSuJ0P"
2) "dNYQiDUtSgq0TaNV1I1ikKliROxeejZx12tFkOka5YAfD2M28c1Oh5ZNTKImkd8lEn3xjmz1qzDgTt19sOLWoD6KSH2fs3GayTA0"
127.0.0.1:6379> HLEN testClass
(integer) 1000
```

然后用 HSCAN 命令扫描 testClass，第一次扫描的时候，游标是 0。返回值的第一行是 192，也就是下次迭代要用的游标值，具体为什么是 192，你现在可以先暂时不用关心，我们也会在解析哈希表底层实现的时候，说这个游标值的具体含义。后面就是返回的 10 条学生指纹。

```shell
127.0.0.1:6379> HSCAN testClass 0
1) "192"
2)  1) "student849"
    2) "fNCL8APpOaV4lGBhRAQ5guzZId1oidlevkolQ3g1efxP28DLj7wY5AFwvScDjiffXrFw14hBIA1sddVnzcGsRxQqjWkAOJckUjfp"
    3)... // 省略后面的输出
```

在继续下一次迭代的时候，我们需要把游标值指定成 192，此次迭代的返回值中，游标值是 160；再往后迭代就要用 160 这个游标值了。

```shell
127.0.0.1:6379> HSCAN testClass 192
1) "160"
2)  1) "student871"
    2) "5V3GprLjtYXDKWe4f7A6pQ7hNKaXxKxb2dXQZwA5wS2qIeoRLqdLIiUIou1QmXG2f4eOSUHyQ65F6kcYTEvgkDVxjmJeuVratqGp"
    3)... // 省略后面的输出

127.0.0.1:6379> HSCAN testClass 160
1) "480"
2)  1) "student893"
    2) "JPrkMjIMxtYEcfr6aZJsBk055K2FNJ3i9y1e0zWPlBiWhm7xRDhn2mJlhbufbWuHu8tDN91Wx9Ts4t1HLSeBj8caV8ZBkG11NJZu"
    3)... // 省略后面的输出
```

下面这张图大概就是 HSCAN 迭代的原理：第一次迭代，从 0 开始，迭代到 192 这个位置，返回的是 0 ~ 192 两个游标之间的内容；然后第二次是从 192 开始迭代，迭代到 160 这个位置，返回的是 192 ~ 160 两个游标之间的内容；第三次是从 160 迭代到 480 这个位置，返回的是 160 ~ 480 两个游标之间的内容。

<img src="assets/00251201c23741d5ac7231a2eb51cccbtplv-k3u1fbpfcp-jj-mark2268000q75.webp" alt="image.png" style="zoom:50%;" />



### 1.3.4 其他命令

#### HLEN

查看有多少条field-value数据

#### HSTRLEN

查看一个value的长度

```SHELL
127.0.0.1:6379> HMGET testHash name age
1) "kouzhaoxuejie"
2) "26"
127.0.0.1:6379> HSTRLEN testHash name
(integer) 13
127.0.0.1:6379> HSTRLEN testHash age
(integer) 2
```

#### HRANDFIELD

从哈希表中随机返回field-value数据.

HRANDFIELD 命令中的 3 这个参数，就是随机返回 field-value 数据的条数，WITHVALUES 参数的含义是同时返回 field 和 value 的值 ，如果不指定 WITHVALUES 的话，就只会返回 3 个 field。

```shell
127.0.0.1:6379> HRANDFIELD testClass 3 WITHVALUES
1) "student848"
2) "VcBYTGptdmdBOPv..."
3) "student565"
4) "QLgIsHXLGrefPS..."
5) "student559"
6) "GkRWcJOZJtuidJz0HQ..."
    
127.0.0.1:6379> HRANDFIELD testClass 3
1) "student47"
2) "student185"
3) "student391"
```



## 1.4 Set

<img src="assets/0f77679eb7824d9ca6c11dc553be72dftplv-k3u1fbpfcp-jj-mark2268000q75.webp" alt="image.png" style="zoom:50%;" />



# 2. 简单动态字符串

简单动态字符串（simple dynamic string, SDS）作用：

- 保存数据库中的字符串值
- 作为缓冲区（AOF模块中的AOF缓冲区，以及客户端状态中的输入缓冲区，都是由SDS实现的）

## 2.1 SDS的定义

```c
struct sdshdr {
    // 记录buf数组中已使用字节的数量
    // 等于SDS所保存字符串的长度
    int len;
    
    // 记录buf数组中未使用字节的数量
    int free;
    
    // 字节数组，用于保存字符串
    char buf[];
};
```

![image-20250723171707428](redis笔记.assets/image-20250723171707428.png)



空字符对SDS的使用者来说是完全透明的。



## 2.2 SDS相较C字符串的优点

### 2.2.1 常数复杂度获取字符串长度

### 2.2.2 杜绝缓冲区溢出

SDS执行拼接操作前，会先检查给定SDS的空间是否足够，如果不够，会先扩展SDS的空间，然后再执行拼接操作

### 2.2.3 减少修改字符串时带来的内存重分配次数

SDS通过free解除了字符串长度和底层数组长度之间的关联：在SDS中，buf数组的长度不一定就是字符数量加一，数组里面可以包含未使用的字节，而这些字节的数量就由SDS的free属性记录。

通过未使用策略，SDS实现了空间预分配和惰性空间释放两种优化策略。

#### 1.空间预分配

当SDS的API对一个SDS进行修改，并且需要对SDS进行空间扩展的时候，程序不仅会为SDS分配修改所需的空间，还会为SDS分配额外的未使用空间。

其中，额外分配的未使用空间数量由以下公式决定：

- 如果对SDS进行修改之后，SDS的长度（即len的值）将小于1MB，那么程序分配和len属性同样大小的未使用空间。eg. 如果进行修改之后，SDS的len将变成13字节，那么程序也会分配13字节的未使用空间， SDS的buf数组的实际长度将变成13+13+1=27字节（额外的一字节用于保存空字符）
- 如果对SDS进行修改之后，len的值将大于等于1MB，那么程序会分配1MB的未使用空间。eg. 如果进行修改之后，SDS的len将变成30MB，那么程序会分配1MB的未使用空间，SDS的buf数组的实际长度将为30MB+1MB+1byte

#### 2. 惰性空间释放

当SDS的API需要缩短SDS保存的字符串时，程序并不立即使用内存重分配来回收缩短后多出来的字节，而是使用free属性将这些字节的数量记录起来。

### 2.2.4 二进制安全

将SDS的buf属性称为字节数组的原因——Redis不是用这个数组来保存字符，而是用它来保存一系列二进制数据。

### 2.2.5 兼容部分C字符串函数

SDS的API遵循以空字符结尾的惯例。

### 2.2.6 总结

![image-20250722112907777](C:\Users\erzhuochen\AppData\Roaming\Typora\typora-user-images\image-20250722112907777.png)



## 2.3 SDS API

![image-20250722112957379](C:\Users\erzhuochen\AppData\Roaming\Typora\typora-user-images\image-20250722112957379.png)

![image-20250722113011158](C:\Users\erzhuochen\AppData\Roaming\Typora\typora-user-images\image-20250722113011158.png)

## 2.4 重点回顾

![image-20250723172335918](redis笔记.assets/image-20250723172335918.png)



# 3. 链表

## 3.1 链表和链表节点的实现

### 3.1.1 链表节点

```c
typedef struct listNode {
    // 前置节点
    struct listNode *prev;
    
    // 后置节点
    struct listNode *next;
    
    // 节点的值
    void *value;
}listNode;
```

### 3.1.2 链表

```c
typedef struct list {
    // 表头节点
    listNode *head;
    
    // 表尾节点
    listNode *tail;
    
    // 链表所包含的节点数量
    unsigned long len;
    
    // 节点值复制函数
    void *(*dup) (void *ptr);
    
    // 节点值释放函数
    void (*free) (void *ptr);
    
    // 节点值对比函数
    int (*match) (void *ptr, void *key);
}list;
```

Redis的链表实现的特性：

- 双端：链表节点带有prev和next指针，获取某个节点的前置节点和后置节点的复杂度都是O(1)
- 无环：表头节点的prev指针和表尾节点的next指针都指向NULL
- 带表头指针和表尾指针
- 带链表长度计数器
- 多态：链表节点使用void*指针来保存节点值，并且可以通过list结构的dup、free、match三个属性为节点值设置类型特定函数，所以链表可以用于保存各种不同类型的值

## 3.2 链表和链表节点的API

![image-20250722170913350](redis笔记.assets/image-20250722170913350.png)

![image-20250722170923855](redis笔记.assets/image-20250722170923855.png)



## 3.3 重点回顾

![image-20250723173148058](redis笔记.assets/image-20250723173148058.png)





# 4. 字典

Redis的数据库就是使用字典来作为底层实现的。

字典是哈希键的底层实现之一，当一个哈希键包含的键值对比较多，又或者键值对中的元素都是比较长的字符串时，Redis就会使用字典作为哈希键的底层实现。



## 4.1 字典的实现

Redis的字典使用哈希表作为底层实现，一个哈希表里面可以有多个哈希表节点，而每个哈希表节点就保存了字典中的一个键值对。



### 4.1.1 哈希表

```c
typedef struct dictht {
    // 哈希表数组
    dicEntry **table;
    
    // 哈希表大小
    unsigned long size;
    
    // 哈希表大小掩码，用于计算索引值
    // 总是等于size-1
    unsigned long sizemask;
    
    // 该哈希表已有节点的数量
    unsigned long used;
    
}dictht;
```



### 4.1.2 哈希表节点

```c
typedef struct dictEntry {
    // 键
    void *key;
    
    // 值
    union{
        void *val;
        uint64_t u64;
        int64_t s64;
    }v;
    
    // 指向下个哈希表节点，形成链表
    struct dictEntry *next;
}dictEntry;
```

![image-20250722172702071](redis笔记.assets/image-20250722172702071.png)



### 4.1.3 字典

```c
typedef struct dict {
    // 类型特定函数
    dictType *type;
    
    // 私有数据
    void *privdata;
    
    // 哈希表 (ht[1]哈希表只会在ht[0]哈希表进行rehash时使用)
    dictht ht[2];
    
    // rehash索引
    // 当rehash不再进行时，值为-1
    int rehashidx;
}dict;
```

```c
typedef struct dictType {
    // 计算哈希值的函数
    unsigned int (*hashFunction) (const void *key);
    
    // 复制键的函数
    void *(*keyDup) (void *privdata, const void *key);
    
    // 复制值的函数
    void *(*valDup) (void *privdata, const void *obj);
    
    // 对比键的函数
    int (*keyCompare) (void *privdata, const void *key1, const void *key2);
    
    // 销毁键的函数
    void (*keyDestructor) (void *privdata, void *key);
    
    // 销毁值的函数
    void (*valDestructor) (void *privdata, void *obj);
    
}dictType;
```



ht[1]哈希表只会在ht[0]哈希表进行rehash时使用。

![image-20250722174057498](redis笔记.assets/image-20250722174057498.png)



## 4.2 哈希算法

**![image-20250722174833138](redis笔记.assets/image-20250722174833138.png)**



## 4.3 解决键冲突

当有两个或以上数量的键被分配到了哈希表数组的同一个索引上面时，这些键发生了**冲突（collision）**。

Redis的哈希表使用链地址法来解决键冲突。



## 4.4 rehash

rehash步骤：

1. 为字典的ht[1]哈希表分配空间，这个哈希表的空间大小取决于要执行的操作，以及ht[0]当前包含的键值对数量( 即ht[0].used )：
   - 如果执行的是扩展操作，那么ht[1]的大小为等于ht[0].used*2的2^n^；
   - 如果执行的是收缩操作，那么ht[1]的大小为第一个大于等于ht[0].used的2^n^.
2. 将保存在ht[0]中的所有键值对rehash到ht[1]上面；rehash指的是重新计算键的哈希值和索引值，然后将键值对放置到ht[1]哈希表的指定位置上。（**注意**：不是复制过去，而是直接放过去）
3. 当ht[0]包含的所有键值对都迁移到了ht[1]之后（ht[0]变为空表），释放ht[0],将ht[1]设置为ht[0]，并在ht[1]新创建一个空白哈希表，为下一次rehash做准备。

### 哈希表的扩展与收缩

当以下条件中的任意一个被满足时，程序会自动开始对哈希表执行扩展操作：

1. 服务器目前没有在执行BGSAVE命令或者BGREWRITRAOF命令，并且哈希表的负载因子大于等于1.
2. 服务器目前正在执行BGSAVE命令或者BGREWRITEAOF命令，并且哈希表的负载因子大于等于5.

哈希表的负载因子计算公式：

![image-20250722191702596](redis笔记.assets/image-20250722191702596.png)

根据BGSAVE命令或BGREWRITEAOF命令是否正在执行，服务器执行扩展操作所需的负载因子并不相同，这是因为在执行BGSAVE命令或BGREWRITEAOF命令的过程中，Redis需要创建当前服务器进程的子进程，而大多数操作系统都采用写时复制（copy-on-write）技术来优化子进程的使用效率，所以在子进程存在期间，服务器会提高执行扩展操作所需的负载因子，从而尽可能地避免不必要的内存写入操作，最大限度地节约内存。

另一方面，当哈希表的负载因子小于0.1时，程序自动开始对哈希表执行收缩操作。



## 4.5 渐进式rehash

详细步骤：

1. 为ht[1]分配空间，让字典同时持有ht[0]和ht[1]两个哈希表
2. 在字典中维持一个索引计数器变量rehashidx，并将它的值设置为0，表示rehash工作正是开始。
3. 在rehash进行期间，每次对字典执行添加、删除、查找或者更新操作时，程序除了执行指定的操作以外，还会顺带将ht[0]哈希表在rehashidx索引上的所有键值对rehash到ht[1]，当rehash工作完成之后，程序将rehashidx属性的值增一。
4. 随着字典操作的不断执行，最终在某个时间点上，ht[0]的所有键值对都会被rehash至ht[1]，这时程序将rehashidx属性的值设为-1，表示rehash操作已完成。

### 渐进式rehash执行期间的哈希表操作

因为在渐进式rehash的过程中，字典会同时使用ht[0]和ht[1]两个哈希表，所以在这期间，字典的删除、查找、更新等操作会在两个哈希表上进行。eg. 要在字典里面查找一个键的话，程序会现在ht[0]里面进行查找，如果没找到，就继续在ht[1]里查找。

在渐进式rehash执行期间，新添加到字典的键值对一律会被保存到ht[1]里面，而ht[0]则不再进行任何添加操作。

## 4.6 字典API

![image-20250722195808450](redis笔记.assets/image-20250722195808450.png)

![image-20250722195815068](redis笔记.assets/image-20250722195815068.png)



## 4.7 重点回顾

![image-20250723180115581](redis笔记.assets/image-20250723180115581.png)



# 5. 跳跃表

跳跃表支持平均O(logN)、最坏O(N)复杂度的节点查找，还可以通过顺序性操作来批量处理节点。

Redis使用跳跃表来作为有序集合键的底层实现之一，如果一个有序集合包含的元素数量比较多，又或者有序集合中元素的成员是比较长的字符串时，Redis就会使用跳跃表来作为有序集合键的底层实现。

Redis只在两个地方用到了跳跃表，一个是实现**有序集合键**，另一个是在**集群节点中用作内部数据结构**。

## 5.1 跳跃表的实现

具体看书

![image-20250722201945836](redis笔记.assets/image-20250722201945836.png)

![image-20250722201955867](redis笔记.assets/image-20250722201955867.png)

![image-20250722202004943](redis笔记.assets/image-20250722202004943.png)

### 5.1.1 跳跃表节点

![image-20250722202138527](redis笔记.assets/image-20250722202138527.png)



### 5.1.2 跳跃表

![image-20250722204119063](redis笔记.assets/image-20250722204119063.png)



## 5.2 跳跃表API

![image-20250722204253176](redis笔记.assets/image-20250722204253176.png)



# 6. 整数集合

整数集合（intset）是集合键的底层实现之一，当一个集合只包含整数值元素，并且这个集合的元素数量不多时，Redis就会使用整数集合作为集合键的底层实现。

 ## 6.1 整数集合的实现

**![image-20250722204523402](redis笔记.assets/image-20250722204523402.png)**



## 6.2 升级

每当我们将一个新元素添加到整数集合里面，并且新元素的类型比整数集合现有所有元素的类型都要长时，整数集合需要先进行升级（upgrade）。

升级整数集合并添加新元素共分为三步进行：

1. 根据新元素的类型，扩展整数集合底层数组的空间大小，并为新元素分配空间
2. 将底层数组现有的所有元素都转换成与新元素相同的类型，并将类型转换后的元素放置到正确的位置上，而且在放置元素的过程中，需要继续维持底层数组的有序性质不变。
3. 将新元素添加到底层数组里面

![image-20250722205938849](redis笔记.assets/image-20250722205938849.png)

![image-20250722210013021](redis笔记.assets/image-20250722210013021.png)

![image-20250722210027544](redis笔记.assets/image-20250722210027544.png)

![image-20250722210037367](redis笔记.assets/image-20250722210037367.png)

## 6.3 升级的好处

### 6.3.1 提升灵活性

不必担心类型错误

### 6.3.2 节约内存



## 6.4 降级

整数集合不支持降级



## 6.5 整数集合API

![image-20250723094821471](redis笔记.assets/image-20250723094821471.png)

## 6.6 重点回顾

![image-20250723094838467](redis笔记.assets/image-20250723094838467.png)



# 7. 压缩列表

压缩列表（ziplist）是列表键和哈希键的底层实现之一。当一个列表键或哈希键只包含少量数据，就会用压缩列表



## 7.1 压缩列表的构成

![image-20250723095428077](redis笔记.assets/image-20250723095428077.png)

![image-20250723095950640](redis笔记.assets/image-20250723095950640.png)

## 7.2 压缩列表节点的构成

![image-20250723100104692](redis笔记.assets/image-20250723100104692.png)



- previous_entry_length：记录了压缩列表中前一个节点的长度
- encoding：记录了节点的content属性所保存数据的类型以及长度
- content：保存节点的值

## 7.3 连锁更新

![image-20250723100904799](redis笔记.assets/image-20250723100904799.png)

新增new时，e1的previous_length的长度不够了，于是增加e1previous_length长度，e1的长度增加后，e2的previous_length长度刚好不够了，以此类推，一系列的“刚好”导致了连锁更新。

新增和删除都会导致连锁更新。

连锁更新在最坏的情况下需要对压缩列表执行N次空间重分配操作，而每次空间重新分配的最坏复杂度为O（N），所以连锁更新的最坏时间复杂度为O（N^2^）。但它真正造成性能问题的几率是很低的。所以ziplistPush等命令的平均复杂度为O(N)。

## 7.4 压缩列表API

![image-20250723105058702](redis笔记.assets/image-20250723105058702.png)





## 7.5 重点回顾

![image-20250723105153057](redis笔记.assets/image-20250723105153057.png)



# 8. 对象

Redis并没有直接使用上述数据结构来实现键值对数据库，而是基于这些数据结构创建了一个对象系统。

## 8.1 对象的类型与编码

![image-20250723105630034](redis笔记.assets/image-20250723105630034.png)



### 8.1.1 类型

![image-20250723105840546](redis笔记.assets/image-20250723105840546.png)

键总是一个字符串对象

当我们称一个键为“列表键”时，我们指的是“这个数据库键所对应的值为列表对象”

![image-20250723110158343](redis笔记.assets/image-20250723110158343.png)



### 8.1.2 编码和底层实现

encoding 属性记录了对象所使用的编码，也即是说这个对象使用了什么数据结构作为对象的底层实现。

![image-20250723110813144](redis笔记.assets/image-20250723110813144.png)

![image-20250723110952765](redis笔记.assets/image-20250723110952765.png)

![image-20250723111315692](redis笔记.assets/image-20250723111315692.png)

## 8.2 字符串对象

embstr编码是专门用于保存短字符串的一种优化编码方式。raw编码会调用两次内存分配函数来分别创建redisObject结构和sdshdr结构（两个空间），而embstr编码则通过调用一次内存分配函数来分配一块连续的空间（一个空间）。

![image-20250723113043149](redis笔记.assets/image-20250723113043149.png)



### 8.2.1 编码的转换

embstr编码的字符串对象实际上是只读的，embstr编码的字符串对象执行任何修改命令时，程序会先将对象的编码从embstr转换成raw，然后再执行修改命令。下图是embstr变成raw的例子：

![image-20250723113350549](redis笔记.assets/image-20250723113350549.png)

### 8.2.2 字符串命令的实现

![image-20250723113505986](redis笔记.assets/image-20250723113505986.png)



## 8.3 列表对象

### 8.3.1 编码转换

满足下面两个条件，用**ziplist**编码：

- 列表对象保存的所有字符串长度都小于64字节
- 列表对象保存的元素数量小于512个

其他情况用**linkedlist**编码



### 8.3.2 列表命令的实现

![image-20250723141249160](redis笔记.assets/image-20250723141249160.png)



## 8.4 哈希对象

编码：

- **ziplist**
- **hashtable**

**ziplist**编码的哈希对象使用压缩列表作为底层实现，每当有新的键值对要加入到哈希对象时，程序会先将保存了键的压缩列表节点推入到压缩列表表尾，然后再将保存了值的压缩列表节点推入到压缩列表表尾，因此：

- 保存了同意键值对的两个节点总是紧挨在一起，保存键的节点在前，保存值的节点在后；
- 先添加到哈希对象中的键值对会被放在压缩列表的表头方向，而后来添加到哈希对象中的键值对会被放在压缩列表的表尾方向。

**hashtable**编码的哈希对象使用字典作为底层实现，哈希对象中的每个键值对都使用一个字典键值对来保存：

- 字典的每个键都是一个字符串对象，对象中保存了键值对的键；
- 字典中的每个值都是一个字符串对象，对象保存了键值对的值



### 8.4.1 编码转换

当哈希对象可以同时满足以下两个条件时，哈希对象使用ziplist编码：

- 哈希对象保存的所有键值对的键和值的字符串长度都小于64字节
- 哈希对象保存的键值对数量小于512个

其他情况用hashtable



### 8.4.2 哈希命令的实现

![image-20250723142953206](redis笔记.assets/image-20250723142953206.png)



## 8.5 集合对象

编码：**insert**或者**hashtable**

hashtable编码的集合对象使用字典作为底层实现，字典的每个键都是一个字符串对象，每个字符串对象包含了一个集合元素，而字典的值则全部都设置为NULL。



### 8.5.1 编码的转换

当集合对象可以同时满足以下两个条件时，对象使用intset编码：

- 集合对象保存的所有元素都是整数值
- 集合对象保存的元素数量不超过512个

其他情况使用hashtable



### 8.5.2 集合命令的实现

![image-20250723144121675](redis笔记.assets/image-20250723144121675.png)



## 8.6 有序集合对象

编码：**ziplist**或者**skiplist**

ziplist：每个集合元素使用两个紧挨在一起的压缩列表节点来保存，第一个节点保存元素的成员（member）,第二个节点保存元素的分值（score）

skiplist：使用zset结构作为底层实现（**注意**：不是单纯的跳跃表），一个zset结构同时包含一个字典和一个跳跃表，见下图

![image-20250723145230581](redis笔记.assets/image-20250723145230581.png)

zset结构中的zsl跳跃表按分值从小到大保存了所有集合元素，每个条约节点都保存了一个集合元素：跳跃表节点的object元素保存了元素的成员，而跳跃表节点的score属性则保存了元素的分值。通过跳跃表，程序可以对有序集合进行**范围型操作**。

zset结构中的dict字典为有序集合创建了一个从成员到分值的映射，字典中的每个键值对都保存了一个集合元素：字典的键保存了元素的成员，而字典的值则保存了元素的分值。通过字典，程序可以用O(1)的复杂度**查找给定成员的分值**，ZSCORE命令就是根据这一特性实现的。

虽然zset结构同时使用跳跃表和和字典来保存有序集合元素，但这两种数据结构都会<u>通过指针来共享相同元素的成员和分值</u>。

有序集合每个元素的成员都是字符串对象，而每个元素的分值都是double类型的浮点数。

### 8.6.1 编码的转换

有序集合对象可以同时满足以下两个条件时，对象使用ziplist编码：

- 有序集合保存的元素数量小于128个
- 有序集合保存的所有元素成员的长度都小于64字节

其他使用skiplist

### 8.6.2 有序集合命令的实现

![image-20250723153351856](redis笔记.assets/image-20250723153351856.png)



## 8.7 类型检查与命令多态

Redistribution用于操作键的命令基本可以分为两种类型：

- 可以对任何类型的键执行的命令
- 只能对特定类型的键执行的命令



### 8.7.1 类型检查的实现

类型特定命令所进行的类型检查是通过redisObject结构的type属性来实现的：

- 在执行一个类型特定命令之前，服务器会先检查输入数据库键的值对象是否为执行命令所需的类型，如果是，服务器就执行该命令
- 否则，服务器拒绝执行命令，并向客户端返回一个类型错误



### 8.7.2 多态命令的实现

书上没说怎么实现



## 8.8 内存回收

每个对象的引用计数信息由redisObject结构的refcount属性记录：

```c
typedef struct redisObject {
    // ...
    //应用计数
    int refcount;
    // ...
}robj;
```

- 在创建一个新对象时，引用计数的值会被初始化为1
- 当对象被一个新程序使用时，它的引用计数值会被增一
- 当对象不再被一个程序使用时，它的引用计数值会被减一
- 当对象的引用计数值变为0时，对象所占用的内存会被释放



## 8.9 对象共享

两个键需要的值对象相同时，共享对象，被共享的值对象的引用计数加一。R**edis只对包含整数值的字符串对象进行共享**。共享包含字符串的对象的话检查操作太耗时了



## 8.10 对象的空转时长

```c
typedef struct redisObject {
    // ...
    //记录对象最后一次被命令程序访问的时间
    unsigned lru:22 
    // ...
}robj;
```



OBJECT IDLETIME命令打印空转时长（=当前时间 - 键的值对象的lru时间）



## 8.11 重点回顾

![image-20250723160649771](redis笔记.assets/image-20250723160649771.png)

# 第二部分

# 9. 数据库

## 9.1 服务器中的数据库

```c
struct redisServer {
    // ...
    
    // 一个数组，保存着服务器中的所有数据库，每个redisDb代表一个数据库
    redisDb *db;
    
    // 服务器的数据库数量
    int dbnum;
    
    // ...
};
```



## 9.2 切换数据库

```c
typedef struct redisClient {
    // ...
    // 记录客户端当前正在使用的数据库
    redisDb *db;
    
    // ...
}redisClient;
```

![image-20250807204930281](assets/image-20250807204930281.png)



## 9.3 数据库键空间

redisDb结构的dict字典保存了数据库中的所有键值对，我们将这个字典称为**键空间**（key space）

```java
typedef struct redisDb {
    // ...
     
    // 数据库键空间，保存着数据库中的所有键值对
    dict *dict;
    
    // ...
} redisDb;
```

键空间和用户所见的数据库是直接对应的：

- 键空间的键就是数据库的键，每个键都是一个字符串对象。
- 键空间的值也是数据库的值，每个值可以是字符串对象、列表对象、哈希表对象、集合对象和有序集合对象中的任意一种Redis对象

### 9.3.1 读写键空间时的维护操作

- 在读取一个键之后，服务器会根据键是否存在来更新服务器的键空间命中（hit）次数或键空间不命中（miss）次数，这两个值可以在INFO stats命令的keyspace_hits属性和keyspace_misses属性中查看。
- 在读取一个键后，服务器会更新键的LRU（最后一次使用）时间，使用OBJECT idletime<key>命令可以查看key的闲置时间
- 如果服务器在读取一个键时发现该键已经过期，那么服务器会先删除这个过期键，再执行余下的其他操作
- 如果有客户端使用WATCH命令监视了某个键，那么服务器再对被监视的键进行修改之后，会将这个键标记为脏（dirty），从而让事务程序注意到这个键已经被修改过，第19章会详细介绍
- 服务器每次修改一个键之后，都会对脏（dirty）键计数器的值增1，这个计数器会触发服务器的持久化以及复制操作，第10、11、15章都会说到
- 如果服务器开启了数据库通知功能，那么在对键进行修改之后，服务器将按配置发送相应的数据库通知。



## 9.4 设置键的生存时间或过期时间

- EXPIRE / PEXPIRE：设置生存时间
- EXPIREAT / PEXPIREAT：设置过期时间
- TTL / PTTL：返回键的剩余生存时间



### 9.4.1 过期字典

```c
typedef struct redisDb {
    // ...
    // 过期字典，保存着键的过期时间
    dict *expires;
    // ...
}redisDb;
```

- 过期字典的键是一个指针，这个指针指向键空间中的某个键对象（也即某个数据库键）
- 过期字典的值是一个long long 类型的整数，保存了键所指向的数据库键的过期时间——一个毫秒精度的UNIX时间戳



### 9.5 过期键删除策略

三种策略：

- 定时删除：设置键的过期时间的同时，创建一个定时器（对CPU最不友好）
- 惰性删除：从键空间获取键时，检查键是否过期，如果过期，就删除（对CPU最友好，对内存最不友好）
- 定期删除：每隔一段时间，对数据库中进行一次检查，删除过期键（对上面两者的折中）

Redis使用**惰性删除**和**定期删除**两种策略。

 

## 9.6 Redis的过期键删除策略 

**惰性删除**策略由`expireIfNeeded`函数实现，所有读写数据库的Redis命令在执行前都会调用`expireIfNeeded`函数检查：

- 如果输入键过期, `expireIfNeeded`函数将输入键从数据库中删除
- 如果未过期,`expireIfNeeded`不做动作

**定期删除**策略由`activeExpireCycle`函数实现, 每当Redis的服务器周期性操作serverCron函数执行时, activeExpireCycle函数就会被调用, 它在规定时间内, 分多次遍历服务器中的各个数据库, 从数据库的expires字典中随机检查一部分键的过期时间, 并删除其中的过期键.



## 9.7 AOF, RDB和复制功能对过期键的处理

**RDB（Redis Database）** 是一种持久化机制，用于将内存中的数据库数据以二进制快照的形式保存到磁盘中。

### 9.7.1 生成RDB文件

在执行SAVE命令或者BGSAVE命令创建一个新的RDB文件时, 程序会对数据库中的键进行检查, 已过期的键不会被保存到新创建的RDB文件中.

举个例子, 如果数据库中包含三个键 k1, k2, k3, 并且k2已经过期, 那么当执行SAVE命令或者BGSAVE命令时, 程序只会将k1和k3的数据保存到RDB文件中, 而k2则会被忽略.

因此, 数据库中包含过期键不会对新的RDB文件造成影响



### 9.7.2 载入RDB文件

在启动Redis服务器时, 如果服务器开启了RDB功能, 那么服务器将对RDB文件进行载入:

- 如果服务器以**主服务器模式**运行, 那么在载入RDB文件时, 程序会对文件中保存的键进行检查, 未过期的键会被载入数据库中, 而过期键则会被忽略, 所以过期键对载入RDB文件的主服务器不会造成影响.
- 如果服务器以**从服务器模式**运行, 那么在载入RDB文件时, 文件中保存的所有键, 不论是否过期, 都会被载入服务器中. 不过, 因为主从服务器在进行数据同步的时候, 从服务器的数据库就会被清空, 所以一般来讲, 过期键对载入RDB文件的从服务器也不会造成影响.

### 9.7.3 AOF文件写入

当服务器以AOF持久化模式运行时, 如果数据库中的某个键已经过期, 但它还没有被惰性删除或者定期删除, 那么AOF文件不会因为这个过期键而产生任何影响.

当过期键被删除之后, 程序会向AOF文件追加(append)一条DEL命令, 来显式地记录该键已被删除.

### 9.7.4 AOF重写

和生成RDB文件时类似, 在执行AOF重写的过程中, 程序会对数据库中的键进行检查, 已过期的键不会被保存到重写后的AOF文件中.



### 9.7.5 复制

当服务器运行在复制模式下时, 从服务器的过期键删除操作由主服务器控制:

- 主服务器在删除一个过期键后, 会显示地向所有从服务器发送一个DEL命令, 告知从服务器删除这个过期键.
- 从服务器在执行客户端发送的读命令时, 即使碰到过期键也不会将过期键删除, 而是继续像处理未过期的键一样来处理过期键
- 从服务器只有在接到主服务器发来的DEL命令后, 才会删除过期键

## 9.8 数据库通知

这个功能可以让客户端通过订阅给定的频道或者模式, 来获知数据库中键的变化, 以及数据库中命令的执行情况.

- <u>关注"某个键执行了什么命令"的通知</u>称为**键空间通知**(key-space notification). (监视某个键)

- <u>关注"某个命令被什么键执行了"的通知</u>称为**键事件通知**(key-event notification). (监视某个命令)

服务器配置的notify-keyspace-events选项决定了服务器所发送通知的类型

![image-20250818111952981](assets/image-20250818111952981.png)



### 9.8.1 发送通知

发送数据库通知的功能是由`notifyKeyspaceEvent`函数实现的:

```c
void notifyKeyspaceEvent(int type, char *event, rboj *key, int dbid);
```

- type: 当前想要发送的通知的类型. 程序会根据这个值来判断通知是否就是服务器配置`notify-keyspace-events`选项所选定的通知类型, 从而决定是否发送通知.
- event:事件的名称.
- key: 产生事件的键.
- dbid: 产生事件的数据库号码

函数根据这四个参数构建事件通知的内容, 以及接收事件的频道名

例如, 一下是`SADD`命令的实现函数`saddCommand`的其中一部分代码:

```c
void saddCommand(redisClient *c){
    // ...
    
    // 如果至少有一个元素被成功添加, 那么执行以下程序
    if(added){
        // ...
        // 发送事件通知
        // REDIS_NOTIFY_SET: 表示这是一个集合键通知
        // "sadd": 事件的名称, 表示这是执行SADD命令所产生的通知 
        notifyKeyspaceEvent(REDIS_NOTIFY_SET, "sadd", c->argv[1], c->db->id);
    }
    
    // ...
}
```



### 9.8.2 发送通知的实现

`notifyKeyspaceEvent`伪代码实现:

```py
def notifyKeyspaceEvetn(type, event, key, dbid){
    # 如果给定的通知不是服务器允许发送的通知, 那么直接返回
    if not(server.notify_keyspace_enents & type):
    	return
    # 发送键空间通知
    if server.notify_keyspace_enents & REDIS_NOTIFY_KEYSPACE:
    	# 将通知发送给频道_keyspace@<dbid>_:<key>
    	# 内容为键所发生的事件 <event>
    
    	# 构建频道名字
    	chan = "_keyspace@{dbid}_:{key}".format(dbid=dbid, key=key)
    	
    	# 发送通知
    	pubsubPublishMessage(chan, event)
    
    # 发送键事件通知
    if server.notify_keyspace_events & REDIS_NOTIFY_KEYEVENT:
    	# 将通知发送给频道
    	# 内容为发生事件的键<key>
    
    	# 构建频道名字
    	chan = "_keyevent@{dbid}_:(event)".format(dbid=dbid, event=event)
    
    	# 发送通知
    	pubsubPublishMessage(chan, key)
}
```

## 9.9 重点回顾

![image-20250818143107518](assets/image-20250818143107518.png)



# 10. RDB持久化

我们将Redis服务器中的非空数据库以及它们的键值对统称为数据库状态

![image-20250818143924883](assets/image-20250818143924883.png)

因为Redis是内存数据库, 它将自己的数据库状态储存在内存里面, 所以如果不想办法, 那么一旦服务器进程退出, 服务器中的数据库状态也会消失不见.

**REB持久化功能**: 可以将某个时间点上的数据库状态保存到一个RDB文件中

RDB文件是一个经过压缩的二进制文件, 通过该文件可以还原生成RDB文件时的数据库状态. 保存在磁盘中.



## 10.1 RDB文件的创建与载入

有两个































































































