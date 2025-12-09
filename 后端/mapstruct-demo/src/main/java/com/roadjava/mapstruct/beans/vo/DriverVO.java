package com.roadjava.mapstruct.beans.vo;

import lombok.Data;

/**
 * @author zhaodaowen
 * @see <a href="http://www.roadjava.com">乐之者java</a>
 */
@Data
public class DriverVO {
    /**
     * 驾驶员id
     */
    private Long driverId;
    /**
     * 驾驶员的名字
     */
    private String fullName;
}
