# 创建服务

`sc create RedisService binPath= "C:\Redis-x64-3.2.100\redis-server.exe --service-run C:\Redis-x64-3.2.100\redis.windows.conf" DisplayName= "Redis" start= auto`

### **1. `sc create`**

- •

  **作用**：Windows 服务控制管理器命令，用于创建新服务

- •

  **语法**：`sc create [服务名称] [参数]`

### **2. `RedisService`**

- •

  **作用**：自定义的服务名称（可任意命名）

- •

  **示例**：可以改为 `MyRedis`、`RedisServer`等

### **3. `binPath=`**

- •

  **作用**：指定服务要执行的程序路径和参数

- •

  **格式**：`binPath= "可执行文件路径 参数"`

- •

  **注意**：**等号后面必须有一个空格**

### **4. `"C:\Redis-x64-3.2.100\redis-server.exe --service-run C:\Redis-x64-3.2.100\redis.windows.conf"`**

- •

  **作用**：Redis 服务的完整启动命令

- •

  **分解**：

  - •

    `C:\Redis-x64-3.2.100\redis-server.exe`：Redis 服务器主程序

  - •

    `--service-run`：Redis 特有的参数，表示以服务方式运行

  - •

    `C:\Redis-x64-3.2.100\redis.windows.conf`：Redis 配置文件路径

### **5. `DisplayName= "Redis"`**

- •

  **作用**：设置服务在服务管理器中的显示名称

- •

  **示例**：在服务列表中会显示为 "Redis"

- •

  **注意**：**等号后面必须有一个空格**

### **6. `start= auto`**

- •

  **作用**：设置服务启动类型为自动

- •

  **可选值**：

  - •

    `auto`：系统启动时自动运行

  - •

    `demand`：手动启动（需要时手动运行）

  - •

    `disabled`：禁用服务

- •

  **注意**：**等号后面必须有一个空格**

# 打开系统配置

`notepad $PROFILE` 用文件夹打开