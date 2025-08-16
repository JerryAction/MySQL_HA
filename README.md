# MySQL_HA **备机房**高可用方案设计

## 方案需求
<img width="1256" height="554" alt="image" src="https://github.com/user-attachments/assets/fbad1932-b3ec-4f51-a6b8-ddc251c67099" />

左边是主机房，右边是备机房。**实现备机房主库高可用**
高可用健壮性：Manager节点进程存活和切换告警可使用以存在的基线配置。

## 方案设计
使用MHA 0.58版本，**修改其代码**解决以下问题：
- 备机房主库MySQL服务异常，30s后自动切换到从库，并重建存活节点的主从关系。
- 故障切换后，重建新主库与主机房的复制链路
  
Tips: **只支持GTID复制。**

**设计的逻辑：**
- MHA 0.58版本为最新版本，支持MySQL8.0，测试版本为MySQL8.0.34。
- 原生代码不支持级联（即是主库又是从库的情况），涉及2个代码文件MasterMonitor.pm和ServerManager.pm只需忽略这种检查即可，其他功能不变。
- 30s后自动切换到从库，可以通过配置文件ping_interval=10 实现，防止网络抖动或是服务重启导致误切换。
- 故障切换后，复制链路，可以通过配置文件添加report_script脚本实现。
- 故障切换的从库，设置candidate_master=1 参与切换，其他从库设置no_master=0 不参与切换。

## 方案内容--核心点
一句话总结：在Manager节点替换2个文件。
- 准备MHA环境，包括主从配置、软件安装、切换脚本配置。
**- 使用新MasterMonitor.pm和ServerManager.pm替换/usr/share/perl5/vendor_perl/MHA目录中的同名文件。**
- 准备复制链路重建脚本rebuild_dc_replication.sh。
### 1. 新代码的逻辑
一句话总结：忽略了主库不可以为从库的限制。

<img width="2216" height="505" alt="image" src="https://github.com/user-attachments/assets/146ee8b1-736c-4b67-b9ca-d8f7277ab15e" />

#### 1.1 循环复制检测
- MasterMonitor.pm ：在 wait_until_master_is_unreachable 和 wait_until_master_is_dead 函数中，通过比较 $real_master 与 $dead_master 的 IP 地址和端口来判断是否为循环复制场景 ( $is_circular 变量)。
- ServerManager.pm ：在 get_primary_master 函数中，当检测到两个主库相互复制时（即每个主库都把另一个主库作为自己的主库），会将其识别为循环复制配置。
#### 1.2  循环复制处理逻辑
- MasterMonitor.pm ：
  - 在循环复制场景下，从存活的主库中选择 $real_master 作为新的主库。
  - 增加了针对循环复制场景的日志记录。
- ServerManager.pm ：
  - 在 get_primary_master 函数中，如果检测到循环复制，会选择其中一个主库作为主主配置中的主库，并记录相关日志。
新ServerManager.pm增加以下内容：

<img width="1373" height="256" alt="image" src="https://github.com/user-attachments/assets/27b1e431-680e-4d53-b89f-4a1f9763640e" />
<img width="1280" height="306" alt="image" src="https://github.com/user-attachments/assets/dd407abf-685e-4b86-b465-20f2ca5be577" />
<img width="1280" height="681" alt="image" src="https://github.com/user-attachments/assets/a0be1652-660c-4d0b-86cd-6334fb3559a9" />
<img width="1280" height="765" alt="image" src="https://github.com/user-attachments/assets/a76d3baa-b3b7-4665-a2ef-c03f31bf1745" />

新MasterMonitor.pm增加以下内容：
<img width="1280" height="797" alt="image" src="https://github.com/user-attachments/assets/c843f27f-4685-42c4-a18c-c8f29fe2d56c" />
<img width="1280" height="494" alt="image" src="https://github.com/user-attachments/assets/f21944a2-d139-4df7-896c-7a95085eecc8" />
<img width="1280" height="768" alt="image" src="https://github.com/user-attachments/assets/e5e13d71-bc36-48a3-9dff-bfbd5f0ea279" />
<img width="1458" height="256" alt="image" src="https://github.com/user-attachments/assets/1e3a433a-8652-451b-bd5d-49855750b8b5" />

### 2. MHA配置文件示例

```bash
配置文件中 
# 修改 为10s 检测一次 所以允许主库失联30s,防止网络抖动或是服务重启导致误切换～
ping_interval=10 

# 添加 重建DC复制的脚本配置项
report_script=/usr/bin/rebuild_dc_replication.sh --cross_dc_master_host=10.186.65.254 --cross_dc_master_port=6630 --new_master_ip=【填写新主库IP】 --new_master_port=【填写新主库port】

cross_dc_master_host为主机房VIP
cross_dc_master_port为主机房MySQL端口
new_master_ip为备机房新主库IP
new_master_port为备机房MySQL端口

# 添加 备机房的非切换从库->不参与切换
no_master=0
```
/data/mha/mha_store_center.conf内容示例：
```bash
[server default]
manager_log=/data/mha/logs/manager.log
manager_workdir=/data/mha/tmp
master_binlog_dir=/data/mha/binlog
master_ip_failover_script=/usr/bin/masterha_ip_failover
master_ip_online_change_script=/usr/bin/masterha_ip_online_change
password=xxx
ping_interval=10
remote_workdir=/data/mha/tmp
repl_password=123456
repl_user=universe_op
report_script=/usr/bin/rebuild_dc_replication.sh --cross_dc_master_host=10.186.65.254 --cross_dc_master_port=6630 --master_ip=10.186.61.9 --master_port=3306
ssh_user=s-mha-user
user=mha

[server1]
candidate_master=1
hostname=10.186.61.75
master_binlog_dir=/data/mysql/log/binlog/3306
port=3306
[server2]
candidate_master=1
hostname=10.186.61.9
master_binlog_dir=/data/mysql/log/binlog/3306
port=3306

[server3]
no_master=0
hostname=10.186.61.23
master_binlog_dir=/data/mysql/log/binlog/3316
port=3316
```

### 3. 链路重建脚本示例
需要修改的3行
```bash
#主机房的VIP和MySQL服务端口
CROSS_DC_MASTER_HOST="10.186.65.254"
CROSS_DC_MASTER_PORT="6630"
# MHA配置文件路径
MHA_CONFIG_FILE="/data/mha/mha_store_center.conf"
```
rebuild_dc_replication.sh脚本内容示例：
```bash
#!/bin/bash

# 跨机房复制重建脚本
# 该脚本将在MHA故障切换完成后自动执行，用于在新主库上重建到另一个机房主库的复制链路

# 初始化变量
MASTER_IP=""
MASTER_PORT=""
REPL_USER=""
REPL_PASSWORD=""
#主机房的VIP和MySQL服务端口
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
```
## 完成切换的日志输出
测试用例说明：
<img width="1256" height="554" alt="image" src="https://github.com/user-attachments/assets/e2a6e0ea-b9b6-4894-94cc-310ad2a75610" />

10.186.61.75 是10.186.61.9和10.186.61.23的主库，也是10.186.65.254的从库。
10.186.61.75 故障后，切换到新主10.186.61.9，并将10.186.61.9作为从库建立与10.186.65.254复制，用于保持机房之间的数据同步。
<img width="1060" height="239" alt="image" src="https://github.com/user-attachments/assets/8bafeaaa-060a-477d-8c5b-3fc5ea0a6873" />

其他测试：

🆗 新编的代码：如果旧主库服务异常：下面的手动切换可以正常执行。
masterha_master_switch --conf=/data/mha/mha_store_center.conf --master_state=dead --dead_master_host=10.186.61.75  --dead_master_port=3306 --new_master_host=10.186.61.9 --new_master_port=3306 --ignore_last_failover 

注意⚠️新编的代码：需要清空旧主复制关系才行，等于是复原为原始MHA架构（不存在循环复制），才能正常执行。
masterha_master_switch --conf=/etc/mha/mha.conf --master_state=alive --new_master_host=10.186.63.112 --new_master_port=3306 --orig_master_is_new_slave


