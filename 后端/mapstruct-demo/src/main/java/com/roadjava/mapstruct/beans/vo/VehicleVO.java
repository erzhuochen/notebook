package com.roadjava.mapstruct.beans.vo;

import lombok.Data;

/**
 * @author zhaodaowen
 * @see <a href="http://www.roadjava.com">乐之者java</a>
 */
@Data
public class VehicleVO {
    /**
     * 编号id
     */
    private Long id;
    /**
     * 裸车的价格
     */
    private Double price;
    /**
     *
     */
    private String brandName;
}
