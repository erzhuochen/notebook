package com.roadjava.mapstruct.beans.vo;

import lombok.Data;

/**
 * @author zhaodaowen
 * @see <a href="http://www.roadjava.com">乐之者java</a>
 */
@Data
public class PartVO {
    /**
     * 汽车零件的id
     */
    private Long partId;
    /**
     * 零件的名字，比如:多功能方向盘
     */
    private String partName;
}
