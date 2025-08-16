#!/bin/bash

# 跨机房复制重建脚本
# 该脚本将在MHA故障切换完成后自动执行，用于在新主库上重建到另一个机房主库的复制链路

# 初始化变量
MASTER_IP=""
MASTER_PORT=""
REPL_USER=""
REPL_PASSWORD=""
CROSS_DC_MASTER_HOST="10.186.65.254"
CROSS_DC_MASTER_PORT="6630"

# MHA配置文件路径
MHA_CONFIG_FILE="/data/mha/mha_store_center.conf"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --master_ip=*)
            MASTER_IP="${1#*=}"
            shift
            ;;
        --master_port=*)
            MASTER_PORT="${1#*=}"
            shift
            ;;
        --repl_user=*)
            REPL_USER="${1#*=}"
            shift
            ;;
        --repl_password=*)
            REPL_PASSWORD="${1#*=}"
            shift
            ;;
        --cross_dc_master_host=*)
            CROSS_DC_MASTER_HOST="${1#*=}"
            shift
            ;;
        --cross_dc_master_port=*)
            CROSS_DC_MASTER_PORT="${1#*=}"
            shift
            ;;
        *)
            # 忽略未知参数
            shift
            ;;
    esac
done

# 检查必需参数
if [ -z "$MASTER_IP" ] || [ -z "$MASTER_PORT" ]; then
    echo "错误: 缺少必需的参数 --master_ip 或 --master_port"
    exit 1
fi

# 如果没有通过命令行参数提供复制用户信息，则从配置文件中读取
if [ -z "$REPL_USER" ] || [ -z "$REPL_PASSWORD" ]; then
    if [ -f "$MHA_CONFIG_FILE" ]; then
        REPL_USER=$(grep "repl_user=" $MHA_CONFIG_FILE | cut -d'=' -f2)
        REPL_PASSWORD=$(grep "repl_password=" $MHA_CONFIG_FILE | cut -d'=' -f2)
        
        if [ -z "$REPL_USER" ] || [ -z "$REPL_PASSWORD" ]; then
            echo "错误: 无法从配置文件 $MHA_CONFIG_FILE 中获取 repl_user 或 repl_password"
            exit 1
        fi
    else
        echo "错误: MHA配置文件 $MHA_CONFIG_FILE 不存在"
        exit 1
    fi
fi

# 查找mysql命令路径
MYSQL_PATH=$(sudo find / -path "*/bin/mysql" -type f -executable 2>/dev/null | head -n 1)

if [ -z "$MYSQL_PATH" ]; then
    echo "错误: 无法找到mysql命令"
    exit 1
fi

echo "使用MySQL命令路径: $MYSQL_PATH"

# 在新主库上执行CHANGE MASTER命令，建立到另一个机房主库的复制
sudo $MYSQL_PATH -h$MASTER_IP -P$MASTER_PORT -u$REPL_USER -p$REPL_PASSWORD -e "STOP SLAVE; RESET SLAVE ALL; CHANGE MASTER TO MASTER_HOST='$CROSS_DC_MASTER_HOST', MASTER_PORT=$CROSS_DC_MASTER_PORT, MASTER_USER='$REPL_USER', MASTER_PASSWORD='$REPL_PASSWORD', MASTER_AUTO_POSITION=1; START SLAVE;" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "成功在新主库 $MASTER_IP:$MASTER_PORT 上重建到 $CROSS_DC_MASTER_HOST:$CROSS_DC_MASTER_PORT 的复制链路"
else
    echo "错误: 在新主库 $MASTER_IP:$MASTER_PORT 上重建复制链路失败"
    exit 1
fi

# 检查复制状态
SLAVE_STATUS=$(sudo $MYSQL_PATH -h$MASTER_IP -P$MASTER_PORT -u$REPL_USER -p$REPL_PASSWORD -e "SHOW SLAVE STATUS\G" 2>/dev/null | grep "Slave_IO_Running:\|Slave_SQL_Running:" | awk '{print $2}')

if [[ "$SLAVE_STATUS" == *"Yes"*"Yes"* ]]; then
    echo "复制状态正常,重建复制链路成功."
else
    echo "警告: 复制状态异常,请检查复制链路."
fi
