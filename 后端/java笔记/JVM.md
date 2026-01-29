## 1. JVM与Java体系结构
### 虚拟机与Java虚拟机简介

**虚拟机**：一台虚拟的计算机。它是一款**软件**，用来执行一系列虚拟计算机指令。可分为系统虚拟机和程序虚拟机。
- **系统虚拟机**：例如 Visual Box, VMware。它们完全是对物理计算机的仿真，提供了一个可运行完整操作系统的软件平台。
- **程序虚拟机**：例如 Java虚拟机。它**专门为执行单个计算机程序而设计**，在Java虚拟机中执行的指令我们称为Java字节码指令。

> *问："Java字节码指令"就是".class"文件中的内容吗?*
> 
> 答：不完全是。.class文件包含以下几个部分：元数据、常量池、类信息、字段表、**方法表**、属性表。
> **方法表**：这里定义了有什么方法（如`main`, 'solve'）。每个方法的结构里有一个叫`Code`属性的区域，**“字节码指令”就放在这个`Code`属性里**。

**Java虚拟机**：一台执行Java字节码的虚拟计算机，它拥有独立运行机制，其运行的Java字节码也未必由Java语言编译而成。
特点：
- 一次编译，到处运行
- 自动内存管理
- 自动垃圾回收功能


### JVM的位置
![](JVM.assets/file-20260127102424665.jpg)
**用户**提供**字节码文件**，**字节码文件**在**JVM**中运行，**JVM**在**操作系统**上运行
系统虚拟机：对硬件的模拟
程序虚拟机：如JVM
![](JVM.assets/file-20260127103031818.png)
JDK：JRE+开发人员用的功能


### JVM的整体结构
简略版
![](JVM.assets/file-20260127103554519.jpg)
详细版
![](JVM.assets/file-20260127103626239.jpg)
中文版
![](JVM.assets/file-20260127105105010.jpg)

### Java代码执行流程
![](JVM.assets/file-20260127113710441.png)

### JVM的架构模型
Java编译器输入的指令流基本上是基于**栈的指令集架构**，另一种指令集架构则是基于**寄存器的指令集架构**。
区别：
- **基于栈式架构**的特点：
	- 设计和实现更简单，适用于资源受限的系统
	- 避开了寄存器的分配难题；使用零地址指令方式分配
	- 指令流中的指令大部分是零地址指令，其执行过程依赖于操作栈。指令集更小，编译器容易实现
	- 不需要硬件支持，可移植性更好，更好实现跨平台
```bash
# 2+3
iconst_2 // 常量2入栈
istore_1
iconst_3 // 常量3入栈
istore_2
iload_1
iload_2
iadd // 常量2、3出栈，执行相加
istore_3 // 结果5入栈
```
- **基于寄存器架构**的特点：
	- 典型的应用是x86的二进制指令集，比如传统的pc以及Android的Davlik虚拟机
	- 指令集架构则完全依赖硬件，可移植性差
	- 性能优秀和执行更高效
	- 花费更少的指令去完成一项操作
	- 在大部分情况下，基于寄存器架构的指令集往往都以一地址指令、二地址指令和三地址指令为主，而基于栈式架构的指令集却是以零地址指令为主
```bash
mov eax,2 // 将eax寄存器的值设为2
add eax,3 // 使eax寄存器的值增加3
```
> 问：零地址指令是什么？
> 
> 答：指令中不包含地址，只有操作数

总结：
由于跨平台性的设计，Java的指令都是根据栈来设计的。不同平台CPU架构不同，所以不能设计为基于寄存器的。优点是**跨平台、指令集小，编译器容易实现**，缺点是**性能下降，实现同样的功能需要更多的指令**。


### JVM的生命周期

**虚拟机的启动**：
Java虚拟机的启动是通过引导类加载器（bootstrap class loader）创建一个初始类（initial class）来完成的，这个类是由虚拟机的具体实现指定的。

**虚拟机的执行**：
- 一个运行中的Java虚拟机有着一个清晰的任务：执行Java程序
- 程序开始执行时它才执行，程序结束时它就停止
- ==执行一个所谓的Java程序的时候，真真正正在执行的是一个叫作Java虚拟机的进程==

**虚拟机的退出**：
有如下几种情况：
- 程序正常执行结束
- 程序在执行过程中遇到了异常或错误而异常终止
- 由于操作系统出现错误而导致Java虚拟机进程终止
- 某线程调用Runtime类或System类的exit方法，或Runtime类的halt方法，并且Java安全管理器也允许这次exit或halt操作
- 除此之外，JNI（Java Native Interface）规范描述了用JNI Invocation API来加载或卸载Java虚拟机时，Java虚拟机的退出情况

### JVM的发展历程

**Sun Classic VM**：
- 世界上第一款商用Java虚拟机
- 内部只提供解释器（效率差）
- 如果使用JIT编译器，就需要进行外挂。但是一旦使用了JIT编译器，JIT就会接管虚拟机的执行系统。解释器就不再工作。解释器和编译器不能配合工作。
- hotspot内置了此虚拟机

**Exact VM**：
- Exact Memory Management: 准确式内存管理
	- 也可以叫Non-Conservative/Accurate Memory Management
	- 虚拟机可以知道内存中某个位置的数据具体是什么类型
- 具备现代高性能虚拟机的雏形
	- 热点探测
	- 编译器与解释器混合工作模式
- 只在Solaris平台短暂使用，其他平台上还是classic vm

**Hotspot VM**:
- 从服务器、桌面到移动端、嵌入式都有应用
- 名称中的HotSpot指的就是它的热点代码探测技术。

**JRockit**：
- 专注于服务端应用
	- 不太关注程序启动速度，全部代码都靠即时编译器编译后执行
- JRockit JVM是世界上最快的JVM
- 优势：全面的Java运行时解决方案组合
	- JRockit面向延迟敏感型应用的解决方案JRockit Real Time提供以毫秒或微秒级的JVM响应时间，适合财务、军事指挥、电信网络的需要
	- MissionControl服务套件，它是一组以极低的开销来监控、管理和分析生产环境中的应用程序的工具

**J9**：
- 全称：IBM Technology for Java Virtual Machine，简称IT4J，内部称号：J9
- 市场定位与HotSpot接近，服务器端、桌面应用、嵌入式等多用途VM


## 2. 类加载子系统
### 概述类的加载器及类加载过程
![](JVM.assets/file-20260127165736736.png)
**类加载器子系统作用**：
- 类加载器子系统负责从文件系统或网络中加载Class文件，class文件在文件开头有特定的文件标识。
- ClassLoader只负责class文件的加载，至于它是否可以运行，则由Execution Engine决定
- 加载的类信息存放在一块称为方法区的内存空间。除了类的信息外，方法区中还会存放运行时常量池信息，可能还包含字符串字面量和数字常量（这部分常量信息是Class文件中常量池部分的内存映射）

**类加载器ClassLoader例子**：
![](JVM.assets/file-20260127170808791.png)
1. class file（Car.class文件） 存在本地硬盘上，可以理解为设计师画在纸上的模板，而最终这个模板在执行的时候是要加载到JVM当中根据这个文件实例化出n个一摸一样的示例
2. class file 加载到JVM中，被称为DNA元数据模板（Car Class），放在方法区
3. 在`.class`文件->JVM->最终成为元数据模板，此过程就要一个运输工具（类装载器 Class Loader），扮演一个快递员的角色
### 类的加载子系统过程一：Loading
**加载阶段：**
1. 通过一个类的全限定名获取定义此类的二进制字节流
2. 将这个字节流所代表的静态结构转化为方法区的运行时数据结构
3. ==在内存中生成一个代表这个类的java.lang.Class对象==，作为方法区这个类的各种数据的访问入口

**补充：加载.class文件的方式**
- 从本地系统中直接加载
- 通过网络获取，典型场景：Web Applet
- 从zip压缩包中读取，成为日后jar、war格式的基础
- 运行时计算生成，使用最多的是：动态代理技术
- 由其他文件生成，典型场景：JSP应用
- 从专有数据库中提取.class文件，比较少见
- 从加密文件中获取，典型的防Class文件被反编译的保护措施

### 类的加载子系统过程二：Linking
![](JVM.assets/file-20260128100833835.png)

> Q: “类变量”和”实例变量“的区别?
> 反思：出现这个问题的主要原因是把类/实例变量 和 类/实例对象 混一起了。类对象是在Loading阶段创建的。
> A: 
> - **类变量 (Class Variable)**：
>    
    - **标识**：被 `static` 关键字修饰的变量（静态变量）。
>        
    - **归属**：属于**类（Class）**本身，而不是某个具体的对象。
>        
>    - **特性**：无论你创建了多少个对象，类变量在内存中**只有一份**，所有对象共享这个变量。
>        
>- **实例变量 (Instance Variable)**：
>    
    - **标识**：没有被 `static` 修饰的普通成员变量。
>        
>    - **归属**：属于具体的**对象实例（Object Instance）**。
>        
>    - **特性**：每当你 `new` 一个新对象，系统就会为这个对象分配一个新的实例变量副本。对象之间互不影响。

### 类的加载子系统过程三：Intialization
- **初始化阶段就是执行类构造器方法`<clinit>()`的过程。**
- 此方法不需定义，自动生成，是javac编译器自动收集类中的**所有类变量的赋值动作和静态代码块中的语句**合并而来。（如果没有类变量和静态代码块，就不会生成`clinit()`方法）
- 构造器方法中指令按语句在源文件中出现的顺序执行
- **`<clinit>()`不同于类的构造器**（关联：构造器是虚拟机视角下的`<init>()`）
- 若该类具有父类，JVM会保证子类的`<clinit>()`执行前，父类的`<clinit>()`已经执行完毕
- 虚拟机必须保证一个类的`<clinit>()`方法在多线程下被同步加锁

总结一下：上述总共涉及.class文件中的两个方法（参考下图）：
- `clinit()`：自动生成，按顺序执行类变量的赋值动作和静态代码块中的语句
- `init()`：类的构造器方法在.class文件中的名字
![](JVM.assets/file-20260128162914618.png)

```java
// 例子
// 在Linking 阶段，初始化类变量num
// 在Intialization阶段，运行clinit()方法按顺序执行赋值动作
public class ClassInitTest {  
    static {  
        num = 2;  
        // System.out.println(num); 会报错，不能前向引用
    }    
    private static int num = 10;  
  
    public static void main(String[] args) {  
        System.out.println(ClassInitTest.num);    
    }
}
```

### 类的加载器的分类
- JVM支持两种类型的类加载器，分别为**引导类加载器**（Bootstrap ClassLoader）和**自定义类加载器**（User-Defined ClassLoader）
- 从概念上来讲，自定义类加载器一般指的是程序中由开发人员自定义的一类类加载器，但是Java虚拟机规范却没有这么定义，而是**将所有派生于抽象类ClassLoader的类加载器都划分为自定义类加载器**
- 无论类加载器的类型如何划分，在程序中我们最常见的类加载器始终只有3个，如下所示：
	- Bootstrap Class Loader：引导类加载器
	- Extension Class Loader：自定义类加载器
	- System Class Loader：自定义类加载器
![](JVM.assets/file-20260128164042431.png)
代码示例：
```java
public class ClassLoaderTest {  
    public static void main(String[] args){  
  
        // 获取系统类加载器  
        ClassLoader systemClassLoader = ClassLoader.getSystemClassLoader();  
        System.out.println(systemClassLoader); //sun.misc.Launcher$AppClassLoader@18b4aac2  
  
        // 获取其上层，扩展类加载器  
        ClassLoader extClassLoader = systemClassLoader.getParent();  
        System.out.println(extClassLoader); // sun.misc.Launcher$ExtClassLoader@1b6d3586  
  
        // 获取上层，获取不到引导类加载器  
        ClassLoader bootstrapClassLoader = extClassLoader.getParent();  
        System.out.println(bootstrapClassLoader); // null  
  
        // 对于用户自定义类来说，默认使用系统类加载器进行加载  
        ClassLoader classLoader = ClassLoaderTest.class.getClassLoader();  
        System.out.println(classLoader);// sun.misc.Launcher$AppClassLoader@18b4aac2  
  
        // String类使用引导类加载器进行加载的 --> Java的核心类都是使用引导类加载器进行加载的
        ClassLoader classLoader1 = String.class.getClassLoader();  
        System.out.println(classLoader1); // null  
    }  
}
```

#### 虚拟机自带的加载器
- 启动类加载器（引导类加载器，Bootstrap ClassLoader）
	- 这个类加载使用



## 3. 运行时数据区概述及线程

## 4. 程序计数器

## 5. 虚拟机栈

## 6. 本地方法接口

## 7. 本地方法栈

## 8. 堆

## 9. 方法区

## 10. 直接内存

## 11. 执行引擎

## 12. StringTable

## 13. 垃圾回收概述

## 14. 垃圾回收相关算法

## 15. 垃圾回收相关概念

## 16. 垃圾回收器

