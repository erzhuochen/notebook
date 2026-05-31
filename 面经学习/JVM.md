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