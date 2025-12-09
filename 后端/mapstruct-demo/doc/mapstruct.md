```shell
java代码简洁之道: mapstruct
```



### 一、mapstruct简介

* 官网 : https://mapstruct.org/  ，使用的版本 **1.3.1.Final**

* 使用场景 ： pojo(参考lombok视频：https://www.bilibili.com/video/BV1T64y1Z7Xm/ ) 之间的相互转化。

  ![image-20201230011846726](image-20201230011846726.png)

* 不同的convert解决方案

  | 名字                                    | 描述                                                  |
  | --------------------------------------- | ----------------------------------------------------- |
  | mapstruct                               | 基于jsr269实现在编译期间生成代码,性能高,精细控制,解耦 |
  | orika                                   | 能够精细控制,解耦                                     |
  | org.springframework.beans.BeanUtils体系 | 简单易用,不能对属性进行定制处理                       |

### 二、mapstruct的使用

#### 2.1 不使用框架的缺点

* 多而杂的代码与业务逻辑耦合,不能==突出业务逻辑的重点==
* 重复的劳动

#### 2.2 @Mapper

* 默认映射规则

  * 同类型且同名的属性，会自动映射

  * mapstruct会自动进行类型转换
    1. 8种基本类型和他们对应的包装类
    2. 8种基本类型(含包装类)和string之间
    3. 日期类型和string

#### 2.3 @Mappings和@Mapping

```java
@Test
public void test2() {
    CarDTO carDTO = buildCarDTO();
    CarVO carVO = CarConvert.INSTANCE.dto2vo(carDTO);
    System.out.println(carVO);
}
```

```java
@Mappings(
            value = {
                    @Mapping(source = "totalPrice",target = "totalPrice",numberFormat = "#.00"),
                    @Mapping(source = "publishDate",target = "publishDate",dateFormat = "yyyy-MM-dd HH:mm:ss"),
                    @Mapping(target = "color",ignore = true),
                    @Mapping(source = "brand",target = "brandName"),
                    @Mapping(source = "driverDTO",target = "driverVO")
            }
    )
    public abstract CarVO dto2vo(CarDTO carDTO);
```

* 指定属性之间的映射关系

  * 日期格式化：dateFormat = "yyyy-MM-dd HH:mm:ss"
  * 数字格式化：numberFormat = "#.00"

* source或target多余的属性对方没有，不会报错的

* ignore `@Mapping(target = "color", ignore = true)` 

* 属性是引用对象的映射处理

  ```java
  @Mapping(source = "driverDTO",target = "driverVO") // 并写上对应的abstract方法
  ```

  ```java
  @Mapping(source = "id",target = "driverId")
      @Mapping(source = "name",target = "fullName")
      public abstract DriverVO driverDTO2DriverVO(DriverDTO driverDTO);
  ```

* 批量映射

```java
/**
 * 测试mapstruct批量转换
 * List<CarDto>--> List<CarVo>
 */
@Test
public void test3() {
    CarDTO carDTO = buildCarDTO();
    List<CarDTO> carDTOList = new ArrayList<>();
    carDTOList.add(carDTO); // source

    // target
    List<CarVO> carVOList = CarConvert.INSTANCE.dtos2vos(carDTOList);
    System.out.println(carVOList);
}
```

```java
/**
 * dto2vo这个方法的批量转换
 */
public abstract List<CarVO> dtos2vos(List<CarDTO> carDTO);
```

#### 2.4 @AfterMapping和@MappingTarget

```java
@AfterMapping // 表示让mapstruct在调用完自动转换的方法之后，会来自动调用本方法
    public void dto2voAfter(CarDTO carDTO,@MappingTarget CarVO carVO) {
        // @MappingTarget : 表示传来的carVO对象是已经赋值过的
        List<PartDTO> partDTOS = carDTO.getPartDTOS();
        boolean hasPart = partDTOS != null && !partDTOS.isEmpty();
        carVO.setHasPart(hasPart);
    }
```



* 在映射最后一步对属性的自定义映射处理

#### 2.5 @BeanMapping

- ignoreByDefault : 忽略mapstruct的默认映射行为。避免不需要的赋值、避免属性覆盖

需要映射的值少的话直接手动set其实也行（但可能不够统一/优雅？）

```java
    /**
     * 配置忽略mapstruct的默认映射行为，只映射那些配置了@Mapping的属性
     * @param carDTO
     * @return
     */
    @BeanMapping(ignoreByDefault = true)
    @Mapping(source = "id",target = "id")
    @Mapping(source = "brand",target = "brandName")
    public abstract VehicleVO carDTO2vehicleVO(CarDTO carDTO);
```

#### 2.6 @InheritConfiguration

* 更新的场景,避免同样的配置写多份

```java
    /**
     * 测试@InheritConfiguration继承配置
     */
    @Test
    public void test5() {
        CarDTO carDTO = buildCarDTO();
        VehicleVO vehicleVO = CarConvert.INSTANCE.carDTO2vehicleVO(carDTO);

        CarDTO carDTO2 = new CarDTO();
        carDTO2.setId(330L);
        carDTO2.setPrice(789d);
        carDTO2.setBrand("迈巴赫");
        // 通过carDTO2的属性值来更新已存在的vehicleVO对象
        CarConvert.INSTANCE.updateVehicleVO(carDTO2,vehicleVO);
        System.out.println(vehicleVO);
    }
```

```java
    /**
     * 会继承全部配置，包括@BeanMapping和@Mapping
     * @param carDTO
     * @param vehicleVO
     */
    @InheritConfiguration(name = "carDTO2vehicleVO")
    public abstract void updateVehicleVO(CarDTO carDTO,@MappingTarget VehicleVO vehicleVO);
```



#### 2.7 @InheritInverseConfiguration

* 反向映射不用反过来再写一遍,==注意：只继承@Mapping注解配置，不会继承@BeanMapping==

#### 2.8 与spring结合使用

```java
@Mapper(componentModel = "spring") // 实质就是给生成的类加了@Component
```



