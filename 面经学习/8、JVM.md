#### JVM指令
##### 一、加载与存储指令
load：从局部变量表压入栈
store：从栈顶弹出并存入局部变量表

const、bipush、ldc：常量压入栈
- iconst_1：用于极小数字
- bipush 10：用于稍大数字
- ldc：用于字符串或大数字

#### 二、方法调用指令
- invokestatic：静态方法
- invokespecial：\<init>, 私有， 父类方法
- invokevirtual：虚方法
- invokeinterface：接口方法
- invokedynamic：lambda

#### 三、对象创建与操作指令
- new：在堆中分配对象内存，并将对象的引用压入操作数栈（注意：此时对象还没有被初始化，只是分配了空间，各个字段都是零值）
- dup：复制栈顶数值并将复制值压入栈顶
	- 为什么：new -> dup
	- 因为紧接着要调用\<init>，这回消耗掉一个引用；为了让后续的代码还能拿到这个对象的引用，必须先复制一份
- getfield/putfield：访问或修改对象的实例字段
- getstatic/putstatic：访问或修改类的静态字段


#### 四、算数与同步指令
- iadd/isub/imul/idiv：对栈顶的两个元素进行加减乘除，弹出这两个数，并将结果压入栈顶
- iinc：直接在局部变量表里对变量进行自增操作，不需要压入操作数栈。
- monitorenter/monitorexit：块的底层原语


#### 对象头
一个Java对象的内存布局分为三部分：对象头（Header）、实例数据（Instance Data）和对齐填充
- Mark Word
- Klass Pointer
- Array Length

##### 一、Mark Word（标记字段）

| **锁状态**                | **25 Bits**                      | **31 Bits**        | **1 Bit** | **4 Bits**      | **1 Bit (偏向标志)** | **2 Bits (锁标志)** |
| ---------------------- | -------------------------------- | ------------------ | --------- | --------------- | ---------------- | ---------------- |
| **无锁 (Normal)**        | unused                           | **HashCode (31位)** | unused    | **GC分代年龄 (4位)** | `0`              | `01`             |
| **偏向锁 (Biased)**       | **ThreadID (54位)**               | **Epoch (2位)**     | unused    | **GC分代年龄 (4位)** | `1`              | `01`             |
| **轻量级锁 (Lightweight)** | **指向栈中 Lock Record 的指针 (62位)**   |                    |           |                 |                  | `00`             |
| **重量级锁 (Heavyweight)** | **指向底层 ObjectMonitor 的指针 (62位)** |                    |           |                 |                  | `10`             |
| **GC 标记 (Marked)**     | 空 (由 GC 算法接管)                    |                    |           |                 |                  | `11`             |
**GC年龄为什么默认最大为15**：GC分代年龄为4bit。
**HashCode在有锁状态时存在哪？**：轻量级锁存在当前线程栈的`Lock Record`中；重量级锁存在`ObjectMonitor`中
**偏向锁和HashCode**：一旦对象调用了Object.hashCode()（注意，调用重写的hashCode没事），就不能使用偏向锁了。
##### 二、 核心骨架二：Klass Pointer（类型指针）

这部分存储的是一个指向方法区（Metaspace）中该对象类的元数据（Klass 结构）的指针。

JVM 通过这个指针来确定这个对象到底属于哪个类。在多态调用、反射、`instanceof` 关键字判断时，底层全靠它。

**高频面试陷阱：Klass Pointer 到底占几个字节？**

- 在纯 64 位环境下，指针应当占用 **8 个字节**。
    
- 但是，为了节省内存，JDK 8 及以后的版本默认开启了**指针压缩**（`-XX:+UseCompressedClassPointers` 和 `-XX:+UseCompressedOops`）。
    
- 开启压缩后，Klass Pointer 被压缩到了 **4 个字节**。这就是为什么我说在开启压缩时，普通对象的头只占 12 个字节（8 字节 Mark Word + 4 字节 Klass Pointer）。
    

##### 三、 核心骨架三：Array Length（数组长度）

仅当对象是数组时存在。占用 **4 个字节**（32位）。

这也解释了为什么 Java 中数组的最大长度不能超过 `Integer.MAX_VALUE`（$2^{31}-1$），因为只有 4 个字节的容量来存长度。

##### 四、 操作系统内存对齐与 Padding

JVM 规范要求，**任何 Java 对象的大小必须是 8 字节的整数倍**。

如果对象头加上实例数据的大小不是 8 的倍数，JVM 就会在对象末尾填充（Padding）空白字节凑齐。

**为什么 OS 和 CPU 层面需要这么做？**

现代 CPU 读取内存不是按字节读的，而是按照缓存行（Cache Line，通常是 64 字节）为单位成块读取。强制对象 8 字节对齐，可以最大程度减少对象跨缓存行存储的概率，提升 CPU 从 L1/L2 缓存读取对象数据的命中率（Cache Hit Rate）。这是典型的“空间换时间”底层工程实践。

##### 五、 工程实践：眼见为实 (JOL)

在架构师的字典里，源码和工具输出是最好的证明。如果你想在实战中查看对象头，建议引入 OpenJDK 提供的 **JOL (Java Object Layout)** 依赖。

XML

```
<dependency>
    <groupId>org.openjdk.jol</groupId>
    <artifactId>jol-core</artifactId>
    <version>0.16</version>
</dependency>
```

**测试代码：**

Java

```
import org.openjdk.jol.info.ClassLayout;

public class ObjectHeaderTest {
    public static void main(String[] args) {
        Object obj = new Object();
        // 打印 obj 对象的内存布局
        System.out.println(ClassLayout.parseInstance(obj).toPrintable());
    }
}
```

**典型的输出结果分析（开启指针压缩）：**

Plaintext

```
java.lang.Object object internals:
 OFFSET  SIZE   TYPE DESCRIPTION                               VALUE
      0     4        (object header)                           01 00 00 00 (00000001 00000000 00000000 00000000) (1)
      4     4        (object header)                           00 00 00 00 (00000000 00000000 00000000 00000000) (0)
      8     4        (object header)                           e5 01 00 f8 (11100101 00000001 00000000 11111000) (-134217243)
     12     4        (loss due to the next object alignment)
Instance size: 16 bytes
```

- 前两行合起来就是 **8 字节的 Mark Word**。
    
- 第三行是 **4 字节的 Klass Pointer**（指针压缩）。
    
- 共 12 字节。因为必须是 8 的倍数，所以最后一行补充了 **4 字节的对齐填充（alignment padding）**，总大小 16 字节。