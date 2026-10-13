#!/usr/bin/env bash
# 越权检查-18：multipart 请求体 userId 校验 —— 手工联调脚本
# 用法：改好下面的配置后  bash multipart-userId校验测试.sh            # 跑网关侧用例（无副作用）
#                       RUN_REAL=1 bash multipart-userId校验测试.sh  # 额外跑真实上传接口用例（有副作用，见文末）
#
# 前置条件（Nacos，代码默认值都是 false）：
#   open_log_business_check=true      # Pre40 总开关，false 时整个 Pre40 不执行，所有用例都会放行
#   open_verify_business_check=true   # 真拦截；false 时只记日志不拦截，下面的“拦截”就要看网关日志判断
#
# 判定方法：
#   - 响应：被 Pre40 拦截时网关直接返回 LOGIN_EXPIRED（code 401）的 JSON；放行时请求会到 wt-web。
#     注意 Pre20 的 token 无效也返回 LOGIN_EXPIRED，所以先跑通用例 01，确认“放行”长什么样。
#   - 网关日志（最准确，开关为 false 时也有）：
#       记录业务校验日志: userId不一致      -> Pre40 判定不一致
#       multipart请求体格式异常 / multipart请求缺少boundary -> 解析失败，返回 null 放行
#       请求userId无法解析为Long          -> parseParamUserId 兜底

set -u

# ================= 配置 =================
GATEWAY="http://localhost:8001"
TOKEN="替换成A登录后拿到的token"
MY_UID="替换成token里的userId"          # 必须等于 token 里的 userId
OTHER_UID="替换成另一个用户的userId"
# 网关侧用例打到一个不存在的路径：Pre40 不看路径（只排除 /web/glc/**），
# 放行后 wt-web 返回 404，不会真的上传文件、也不会处理旧文件
PROBE_PATH="/web/__pre40_probe/upload"

# 真实接口用例（RUN_REAL=1 时才跑）：请用测试账号和测试收款人
REAL_PATH="/web/payee/document/upload/single"
REAL_PAYEE_ID="替换成测试收款人id"
REAL_FILE_TYPE="替换成fileType"
# ========================================

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
B="----pre40TestBoundary7MA4YWxkTrZu0gW"

# 1KB 和 10MB 的随机二进制“文件”
head -c 1024 /dev/urandom > "$TMP/small.bin"
head -c $((10 * 1024 * 1024)) /dev/urandom > "$TMP/big.bin"

# ---- 构造 multipart 请求体（全部手写，part 顺序和边界格式完全可控）----
# 用法：body <输出文件> <part>...   part 形如  text:name=value  |  file:name=filename@本地文件  |  raw:任意字节串（printf 格式）
body() {
  local out=$1; shift
  : > "$out"
  for p in "$@"; do
    case $p in
      text:*)
        local kv=${p#text:}
        printf -- '--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n' "$B" "${kv%%=*}" "${kv#*=}" >> "$out" ;;
      file:*)
        local kv=${p#file:} name fn src
        name=${kv%%=*}; fn=${kv#*=}; src=${fn#*@}; fn=${fn%%@*}
        printf -- '--%s\r\nContent-Disposition: form-data; name="%s"; filename="%s"\r\nContent-Type: application/octet-stream\r\n\r\n' "$B" "$name" "$fn" >> "$out"
        cat "$src" >> "$out"
        printf '\r\n' >> "$out" ;;
      raw:*)
        printf -- "${p#raw:}" >> "$out" ;;
    esac
  done
}
close() { printf -- '--%s--\r\n' "$B" >> "$1"; }

# 用法：send <编号> <说明> <预期> <请求体文件> [content-type] [query] [path]
send() {
  local id=$1 desc=$2 expect=$3 file=$4
  local ctype=${5:-"multipart/form-data; boundary=$B"} query=${6:-} path=${7:-$PROBE_PATH}
  local url="$GATEWAY$path${query:+?$query}"
  echo "=================================================================="
  echo "[$id] $desc"
  echo "     预期：$expect"
  local meta
  meta=$(curl -s -o "$TMP/resp" -w '%{http_code} %{time_total}s' \
    -H "token: $TOKEN" -H "Content-Type: $ctype" \
    --data-binary @"$file" "$url")
  echo "     HTTP $meta  请求体 $(wc -c < "$file") 字节"
  echo "     响应：$(head -c 300 "$TMP/resp")"
}

# ======================= 网关侧用例（无副作用） =======================

body "$TMP/01" text:userId=$MY_UID file:file=a.jpg@"$TMP/small.bin"; close "$TMP/01"
send 01 "基线：表单 userId=自己，参数在文件前" "放行" "$TMP/01"

body "$TMP/02" text:userId=$OTHER_UID file:file=a.jpg@"$TMP/small.bin"; close "$TMP/02"
send 02 "越权：表单 userId=他人，query 不带（本次修复的目标）" "拦截；日志 userId不一致（改动前会放行）" "$TMP/02"

body "$TMP/03" file:file=a.jpg@"$TMP/small.bin" text:userId=$OTHER_UID; close "$TMP/03"
send 03 "越权：userId 排在文件之后，需扫过文件内容" "拦截" "$TMP/03"

body "$TMP/04" text:userId=$OTHER_UID file:file=a.jpg@"$TMP/small.bin"; close "$TMP/04"
send 04 "query=自己、表单=他人：网关以 query 为准" "放行（上游实际绑定哪个见 R1）" "$TMP/04" "" "userId=$MY_UID"

body "$TMP/05" text:userId=$MY_UID file:file=a.jpg@"$TMP/small.bin"; close "$TMP/05"
send 05 "query=他人（改动前就有的逻辑，回归）" "拦截" "$TMP/05" "" "userId=$OTHER_UID"

printf '%s' "$OTHER_UID" > "$TMP/uid.txt"
body "$TMP/06" file:userId=uid.txt@"$TMP/uid.txt" file:file=a.jpg@"$TMP/small.bin"; close "$TMP/06"
send 06 "文件 part 的字段名也叫 userId（内容是他人id），没有文本 userId" "放行（带 filename 的 part 被跳过）" "$TMP/06"

body "$TMP/07" file:userId=uid.txt@"$TMP/uid.txt" text:userId=$MY_UID file:file=a.jpg@"$TMP/small.bin"; close "$TMP/07"
send 07 "同名文件 part(他人) 在前，文本 userId=自己 在后" "放行（取的是文本字段）" "$TMP/07"

body "$TMP/08" text:userId=$OTHER_UID file:file=a.jpg@"$TMP/small.bin"; close "$TMP/08"
send 08 "boundary 带引号" "拦截（证明能去掉引号并解析）" "$TMP/08" "multipart/form-data; boundary=\"$B\""

body "$TMP/09" raw:'this is preamble\r\n' text:userId=$OTHER_UID file:file=a.jpg@"$TMP/small.bin"; close "$TMP/09"
send 09 "首个边界前有 preamble" "拦截" "$TMP/09"

body "$TMP/10" text:userId=$OTHER_UID raw:"--$B\r\nContent-Disposition: form-data; name=\"x\"\r\n\r\nno-end"
send 10 "请求体截断：最后一个 part 没有结束边界，userId=他人 在截断点之前" "拦截；找到即停，碰不到截断处，不打格式异常 warn" "$TMP/10"

body "$TMP/11" raw:"--$B\r\nContent-Disposition: form-data; name=\"userId\"\r\n\r\n$OTHER_UID"
send 11 "请求体截断：userId 这个 part 本身没有结束边界" "放行；日志 multipart请求体格式异常 part缺少结束边界（下游 Tomcat 也会解析失败）" "$TMP/11"

body "$TMP/12" text:userId=$OTHER_UID; close "$TMP/12"
send 12 "Content-Type 没有 boundary 参数" "放行；日志 multipart请求缺少boundary" "$TMP/12" "multipart/form-data"

body "$TMP/13" text:userId=0x7B file:file=a.jpg@"$TMP/small.bin"; close "$TMP/13"
send 13 "userId=0x7B（Spring 能绑定成 123，parseLong 不接受）" "拦截；日志 请求userId无法解析为Long + userId不一致" "$TMP/13"

printf '{"userId":"%s","foo":"bar"}' "$OTHER_UID" > "$TMP/14"
send 14 "非 multipart：JSON 请求体 userId=他人（回归）" "拦截（走原有正则）" "$TMP/14" "application/json"

printf '{"userId":"%s","foo":"bar"}' "$MY_UID" > "$TMP/15"
send 15 "非 multipart：JSON 请求体 userId=自己（回归）" "放行" "$TMP/15" "application/json"

# ---- 性能：10MB，对比 userId 在文件前 / 后的耗时差，差值约等于扫描开销 ----
body "$TMP/16" text:userId=$MY_UID file:file=big.bin@"$TMP/big.bin"; close "$TMP/16"
send 16 "性能：10MB，userId 在文件前（找到即停）" "放行；记下耗时" "$TMP/16"

body "$TMP/17" file:file=big.bin@"$TMP/big.bin" text:userId=$MY_UID; close "$TMP/17"
send 17 "性能：10MB，userId 在文件后（扫过 10MB）" "放行；耗时与 16 对比" "$TMP/17"

body "$TMP/18" file:file=big.bin@"$TMP/big.bin"; close "$TMP/18"
send 18 "性能：10MB，没有 userId（扫完整个请求体）" "放行；耗时与 16 对比" "$TMP/18"

# ======================= 真实接口用例（有副作用） =======================
# 打到真实的 /upload/single：会真的上传文件、调用 dealOldDocuments 处理该收款人同 fileType 的旧文件、插入新记录。
# 只用测试账号 + 测试收款人跑。
if [ "${RUN_REAL:-0}" = "1" ]; then
  echo
  echo "##################### 真实接口用例 #####################"

  body "$TMP/R1" text:userId=$OTHER_UID text:payeeId=$REAL_PAYEE_ID text:fileType=$REAL_FILE_TYPE file:file=r1.jpg@"$TMP/small.bin"; close "$TMP/R1"
  send R1 "query=自己、表单=他人：验证上游 controller 绑定的 userId" \
    "网关放行；再看 wt-web 日志“收款人文件上传订单号:{...}”里的 userId，应是自己（$MY_UID）。若是他人，说明 query 优先的假设不成立，存在绕过" \
    "$TMP/R1" "" "userId=$MY_UID" "$REAL_PATH"

  body "$TMP/R2" text:userId=$OTHER_UID text:payeeId=$REAL_PAYEE_ID text:fileType=$REAL_FILE_TYPE file:file=r2.jpg@"$TMP/small.bin"; close "$TMP/R2"
  send R2 "真实接口越权：表单 userId=他人" "拦截，wt-web 没有收到这次请求（没有“收款人文件上传订单号”日志）" "$TMP/R2" "" "" "$REAL_PATH"
fi
