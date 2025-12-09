package com.roadjava.mapstruct;

import com.roadjava.mapstruct.beans.dto.CarDTO;
import com.roadjava.mapstruct.beans.dto.DriverDTO;
import com.roadjava.mapstruct.beans.dto.PartDTO;
import com.roadjava.mapstruct.beans.vo.CarVO;
import com.roadjava.mapstruct.beans.vo.DriverVO;
import com.roadjava.mapstruct.beans.vo.VehicleVO;
import com.roadjava.mapstruct.convert.CarConvert;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mapstruct.factory.Mappers;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.junit4.SpringRunner;

import javax.annotation.Resource;
import java.text.DecimalFormat;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.List;


/**
 * @author zhaodaowen
 * @see <a href="http://www.roadjava.com">乐之者java</a>
 */
@RunWith(SpringRunner.class)
@SpringBootTest(classes = MapStructApplication.class)
public class MapStructTest {
//    @Autowired
    @Resource
    private CarConvert carConvert;

    /**
     * 测试mapstruct和spring整合
     */
    @Test
    public void test7() {
        VehicleVO vehicleVO = new VehicleVO();
        vehicleVO.setId(9999L);
        vehicleVO.setBrandName("别克");
        vehicleVO.setPrice(66554322d);
        CarDTO carDTO = carConvert.vehicleVO2CarDTO(vehicleVO);
        System.out.println(carDTO);
    }

    /**
     * 测试@InheritInverseConfiguration反向继承
     */
    @Test
    public void test6() {
       VehicleVO vehicleVO = new VehicleVO();
       vehicleVO.setId(9999L);
       vehicleVO.setBrandName("别克");
       vehicleVO.setPrice(66554322d);
        CarDTO carDTO = CarConvert.INSTANCE.vehicleVO2CarDTO(vehicleVO);
        System.out.println(carDTO);
    }


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

    /**
     * 测试@BeanMapping
     */
    @Test
    public void test4() {
        CarDTO carDTO = buildCarDTO();
        VehicleVO vehicleVO = CarConvert.INSTANCE.carDTO2vehicleVO(carDTO);
        System.out.println(vehicleVO);
    }

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
    /**
     * 测试mapstruct
     * CarDto-->CarVo
     */
    @Test
    public void test2() {
        CarDTO carDTO = buildCarDTO();
        CarVO carVO = CarConvert.INSTANCE.dto2vo(carDTO);
        System.out.println(carVO);
    }

    /**
     * 测试传统的通过getter和setter赋值完成pojo之间转换
     * CarDto-->CarVo
     */
    @Test
    public void test1() {
        // 模拟业务构造出的CarDTO对象
       CarDTO carDTO = buildCarDTO();
       // 转化dto-vo
        CarVO carVO = new CarVO();
        carVO.setId(carDTO.getId());
        carVO.setVin(carDTO.getVin());
        carVO.setPrice(carDTO.getPrice()); // 装箱拆箱机制，不需要我们自己转化

        double totalPrice = carDTO.getTotalPrice();
        DecimalFormat df = new DecimalFormat("#.00");
        String totalPriceStr = df.format(totalPrice);
        carVO.setTotalPrice(totalPriceStr);

        Date publishDate = carDTO.getPublishDate();
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
        String publishDateFormat = sdf.format(publishDate);
        carVO.setPublishDate(publishDateFormat);

        carVO.setBrandName(carDTO.getBrand());

        List<PartDTO> partDTOS = carDTO.getPartDTOS();
        boolean hasPart = partDTOS != null && !partDTOS.isEmpty();
        carVO.setHasPart(hasPart);

        DriverVO driverVO = new DriverVO();
        DriverDTO driverDTO = carDTO.getDriverDTO();
        driverVO.setDriverId(driverDTO.getId());
        driverVO.setFullName(driverDTO.getName());
        carVO.setDriverVO(driverVO);

        System.out.println(carVO);
    }

    /**
     * 模拟业务构造出的CarDTO对象
     * @return
     */
    private CarDTO buildCarDTO() {
        CarDTO carDTO = new CarDTO();
        carDTO.setId(330L);
        carDTO.setVin("vin123456789");
        carDTO.setPrice(123789.126d);
        carDTO.setTotalPrice(143789.126d);
        carDTO.setPublishDate(new Date());
        carDTO.setColor("白色");
        carDTO.setBrand("大众");
        // 零件
        PartDTO partDTO1 = new PartDTO();
        partDTO1.setPartId(1L);
        partDTO1.setPartName("多功能方向盘");
        PartDTO partDTO2 = new PartDTO();
        partDTO2.setPartId(2L);
        partDTO2.setPartName("智能车门");
        List<PartDTO> partDTOList = new ArrayList<>();
        partDTOList.add(partDTO1);
        partDTOList.add(partDTO2);
        carDTO.setPartDTOS(partDTOList);
        // 设置驾驶员
        DriverDTO driverDTO = new DriverDTO();
        driverDTO.setId(88L);
        driverDTO.setName("小明");
        carDTO.setDriverDTO(driverDTO);
        return carDTO;
    }
}
