package com.roadjava.mapstruct.beans.dto;

import lombok.Data;

import java.util.Date;
import java.util.List;

/**
 * @author zhaodaowen
 * @see <a href="http://www.roadjava.com">乐之者java</a>
 */
@Data
public class CarDTO {
    /**
     * 编号id
     */
    private Long id;
    /**
     * 车辆的编号
     */
    private String vin;
    /**
     * 裸车的价格,单位:元
     */
    private double price;
    /**
     * 上路的价格,单位:元
     */
    private double totalPrice;
    /**
     * 生产日期
     */
    private Date publishDate;
    /**
     * 车的颜色,不想映射给vo
     */
    private String color;
    /**
     * 品牌名字
     */
    private String brand;
    /**
     * 汽车包含的零件列表
     */
    private List<PartDTO> partDTOS;
    /**
     * 汽车的司机
     */
    private DriverDTO driverDTO;

}
