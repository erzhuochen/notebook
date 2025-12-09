package com.roadjava.mapstruct.beans.vo;

import lombok.Data;

/**
 * @author zhaodaowen
 * @see <a href="http://www.roadjava.com">乐之者java</a>
 */
@Data
public class CarVO {
    /**
     * 编号id
     */
    private Long id;
    /**
     * 车辆的编号
     */
    private String vin;
    /**
     * 裸车的价格
     */
    private Double price;
    /**
     * 上路的价格,保留两位小数
     */
    private String totalPrice;
    /**
     * 生产日期，格式yyyy-MM-dd HH:mm:ss
     */
    private String publishDate;
    /**
     * 车的颜色
     */
    private String color;
    /**
     * 品牌名字
     */
    private String brandName;
    /**
     * 是否配置了零件
     */
    private Boolean hasPart;
    /**
     * 汽车的司机
     */
    private DriverVO driverVO;

}
