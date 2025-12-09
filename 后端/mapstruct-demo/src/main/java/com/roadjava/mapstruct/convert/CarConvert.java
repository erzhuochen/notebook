package com.roadjava.mapstruct.convert;

import com.roadjava.mapstruct.beans.dto.CarDTO;
import com.roadjava.mapstruct.beans.dto.DriverDTO;
import com.roadjava.mapstruct.beans.dto.PartDTO;
import com.roadjava.mapstruct.beans.vo.CarVO;
import com.roadjava.mapstruct.beans.vo.DriverVO;
import com.roadjava.mapstruct.beans.vo.VehicleVO;
import org.mapstruct.*;
import org.mapstruct.factory.Mappers;
import org.springframework.beans.factory.annotation.Autowired;

import java.util.List;

/**
 * 使用mapstruct的步骤:
 *  1.引入依赖
 *  2.新建一个抽象类或者接口并标注@Mapper
 *  3.写一个转换方法，方法名字是任意的，没有要求
 *  4.获取对象INSTANCE并使用
 * car相关的pojo之间的转化
 * @author zhaodaowen
 * @see <a href="http://www.roadjava.com">乐之者java</a>
 */
@Mapper(componentModel = "spring")
public abstract class CarConvert {
    public static CarConvert INSTANCE = Mappers.getMapper(CarConvert.class);
//
//    @Autowired
//    private UserService userService;

    /**
     * CarDto-->CarVo
     */
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

    /**
     * driverDTO-->driverVO
     * @param driverDTO
     * @return
     */
    @Mapping(source = "id",target = "driverId")
    @Mapping(source = "name",target = "fullName")
    public abstract DriverVO driverDTO2DriverVO(DriverDTO driverDTO);

    @AfterMapping // 表示让mapstruct在调用完自动转换的方法之后，会来自动调用本方法
    public void dto2voAfter(CarDTO carDTO,@MappingTarget CarVO carVO) {
        // @MappingTarget : 表示传来的carVO对象是已经赋值过的
        List<PartDTO> partDTOS = carDTO.getPartDTOS();
        boolean hasPart = partDTOS != null && !partDTOS.isEmpty();
        carVO.setHasPart(hasPart);
    }

    /**
     * dto2vo这个方法的批量转换
     */
    public abstract List<CarVO> dtos2vos(List<CarDTO> carDTO);

    /**
     * 配置忽略mapstruct的默认映射行为，只映射那些配置了@Mapping的属性
     * @param carDTO
     * @return
     */
    @BeanMapping(ignoreByDefault = true)
    @Mapping(source = "id",target = "id")
    @Mapping(source = "brand",target = "brandName")
    public abstract VehicleVO carDTO2vehicleVO(CarDTO carDTO);


    /**
     * 会继承全部配置，包括@BeanMapping和@Mapping
     * @param carDTO
     * @param vehicleVO
     */
    @InheritConfiguration(name = "carDTO2vehicleVO")
    public abstract void updateVehicleVO(CarDTO carDTO,@MappingTarget VehicleVO vehicleVO);

    /**
     * 测试@InheritInverseConfiguration反向继承，只会继承@Mapping
     * 故需要再单独写一次 @BeanMapping
     * name:指定使用哪一个方法的配置,写方法的名字
     * @param vehicleVO
     * @return
     */
    @BeanMapping(ignoreByDefault = true)
    @InheritInverseConfiguration(name = "carDTO2vehicleVO")
    public abstract CarDTO vehicleVO2CarDTO(VehicleVO vehicleVO);
}
