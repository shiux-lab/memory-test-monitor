#!/bin/bash
# 检查 ipmitool 是否安装
if command -v ipmitool &>/dev/null; then
    :
else
    # 如果未安装，则提示用户安装并退出
    echo "ipmitool is not installed. Please install ipmitool before continuing."
    exit 1
fi
# 可改参数：
# 服务器代数；可填写这些内容："G5" "G6" "G7" "KPG3"
# eg:gen="G7"
gen="G7"
# 服务器型号，除R4960外，其他可以不做修改，保持XX即可
server_type="xx"
# sleep_time: 进入 OS 的一段睡眠时间，单位是s
sleep_time="110"
# wait_time:  cold reboot掉电到唤醒的时间，单位是s
wait_time="110"
# react_time: 进入 OS 到该脚本开始收集 OS 信息的机器缓冲时间
react_time="0"
# port_up_time: 进入 OS 到收集网口状态的时间，出现reboot检测到网口状态不一致，进入系统后发现网口状态正常时可以进行适当延长该时间
port_up_time="5"
# reboot_cancel_flag：非重启标记，测试执行完成不重启，用于带外控制时系统下信息校验或其他定位场景
reboot_cancel_flag=0
# hooks_set_up: 自定义命令执行在option检查前，先进行检查再运行自定义命令

#选择使用的ac_ctl设备：1表示ac盒子，2表示PDU，默认ac盒子
pdu_flag="1"
#当前服务器使用AC盒子OUTPUT端口:使用单口改为A或者B，使用双口改为AB，若pdu_flag=2，则无需改动
box_output_port="A"
#当前服务器使用PDU的OUTPUT端口:值为1-8，根据实际使的端口设置，若使用两个口需要用逗号隔开如1,2，若pdu_flag=1，则无需改动
pdu_part="1"
#设置盒子或者PDU的IP地址，与pdu_flag=1/2对应，根据实际修改
box_ip="192.168.6.135"·


hooks_set_up='
    # 命令形式支持SHELL语法范围, 书写习惯无限制，常用命令, 循环, 判断，脚本等。
    # 命令支持独立子SHELL中执行, 变量设置无限制, 可使用当前脚本中支持的变量, 此变量中的变量仅在自定义脚本范围中有效。
    # 需要log文件请以hooks开始, eg: hooks_xxx.log
    # sh hooks_test.sh
    # for i in {1..5}
    # do
    #     echo "hooks test OK" >> hooks_test.log
    # done
'
# hooks_set_down: 自定义命令执行在option检查后，先运行自定义命令再执行检查
hooks_set_down='
    # 参考hooks_set_up，一致
    # echo hooks down test OK >> hooks_test.log
'
#调用Python，给AC盒子下发下电指令，不可修改
pwrctl() {
  python3 - "$@" <<EOF
#!/usr/bin/python3
import argparse
import datetime
import re
import socket
import sys
import time
import urllib.request, urllib.parse, urllib.error
import urllib.request, urllib.error, urllib.parse
import requests
from requests.auth import HTTPBasicAuth

TIMEOUT = 10
DELAY = '90'
SOCKET_COUNT = 2
MAX_SOCKET = 8
MAX_BIT = 24
AUTH = "c25tcDoxMjM0"
#AUTH = "YWRtaW46c2lnODhzaWc="
auth = HTTPBasicAuth("snmp", "1234")

class Error(Exception):
    def __init__(self, msg):
        self.msg = msg

    def __str__(self):
        return self.msg

    def __repr__(self):
        return self.msg

def http_request(url):
    res = requests.post(url,auth=auth, data=None, json=None, verify=False, timeout=1)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ip", 
                        help="IP address of remote power switch, default 192.168.0.200")
    parser.add_argument("socket", 
                        nargs='?',
                        default='11',
                        help="which socket to be power OFF/ON, format is 'xx', x is 1 or 0, 1 means apply, 0 means ignore. Default '11', powering OFF/ON two sockets")
    parser.add_argument("delay",
                        nargs='?',
                        default=','.join([DELAY]*SOCKET_COUNT),
                        help="power ON delay time(seconds) for two sockets, format is 'x,x'. Default '%s', two sockets will be power OFF/ON with %s seconds delay" % (','.join([str(DELAY)]*SOCKET_COUNT), DELAY))
    parser.add_argument("-v", "--verbose", action="store_true", help="increase output verbosity")
    args = parser.parse_args()

    # socket argument must be like pattern 'xx', x is 1 or 0
    socket_regex = re.compile('[01]{2}')
    if not socket_regex.match(args.socket):
        parser.print_help()
        raise Error("socket argument is not correct, accepted pattern is like 'xx', x is 1 or 0")

    # delay argument must be like pattern 'x,x', x is a number
    delay_regex = re.compile("\d+,\d+")
    if not delay_regex.match(args.delay):
        parser.print_help()
        raise Error("delay argument is not correct, accepted pattern is like 'x,x', x is a number")

    # Firstly, set power OFF delay time of each socket to 0 seconds
    # max eight sockets, e.g. http://192.168.1.87/delayf1.cgi?led=0,0,0,0,0,0,0,0,0,
    offdelay_url = "http://%s/delayf1.cgi?led=0,0,0,0,0,0,0,0,0," % args.ip
    if args.verbose:
        print(offdelay_url)
    http_request(offdelay_url)

    # use delay argument to set power ON delay time for each socket
    # e.g. http://192.168.1.87/delay1.cgi?led=0,90,90,90,90,90,90,90,90,
    ondelay_url = "http://%s/delay1.cgi?led=0," % args.ip
    # two sockets: http://192.168.1.87/delay1.cgi?led=0,90,90,0,0,0,0,0,0,
    ondelay_url += args.delay + ',' + ','.join(['0']*(MAX_SOCKET-SOCKET_COUNT)) + ','
    if args.verbose:
        print(ondelay_url)
    http_request(ondelay_url)

    # control which sockets to turn off/on, max 24 bits  
    # e.g. turn off/on two sockets: http://192.168.1.87/offon.cgi?led=110000000000000000000000
    offon_url = "http://%s/offon.cgi?led=%s" % (args.ip, args.socket+'0'*(MAX_BIT-SOCKET_COUNT))

    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print("%s: remote power switch <%s> will power OFF <%s> sockets and power ON after <%s> seconds" % (now, args.ip, args.socket.count('1'), args.delay))
    if args.verbose:
        print(offon_url)
    http_request(offon_url)

if __name__ == "__main__":
    main()
    print('Turn off two sockets success')
EOF

}

pductl() {
  python3 - "$@" <<EOF
import re
import requests
import argparse
import time

requests.packages.urllib3.disable_warnings()


class APCPDUController:
    LOGIN_URL = "home.htm"
    LOGIN_FORM_URL = "Forms/login1"
    OUTLCTRL_URL = "outlctrl.htm"
    OUTLCTRL_FORM_URL = "Forms/outlctrl1"
    RPDU_CONF_FORM_URL = "Forms/rpduconf1"

    def __init__(self, pdu_ip, username="apc", password="apc", debug=False):
        self.pdu_ip = pdu_ip
        self.URL = f"http://{pdu_ip}/"
        self.URL_BASE = f"http://{pdu_ip}/NMC/"
        self.session = requests.Session()
        self.session.verify = False
        self.username = username
        self.password = password
        self.debug = debug

    def _debug_print(self, msg):
        if self.debug:
            print(f"[DEBUG] {msg}")

    def request_get(self, url):
        resp = self.session.get(url, allow_redirects=False, verify=False)
        self._debug_print(f"GET {url} -> {resp.status_code}")
        return resp

    def request_post(self, url, data=None):
        resp = self.session.post(
            url, data=data, allow_redirects=False, verify=False)
        self._debug_print(f"POST {url} Data={data} -> {resp.status_code}")
        return resp

    def _login(self):
        home_url = f"{self.URL}{self.LOGIN_URL}"
        resp = self.request_get(home_url)
        location = resp.headers.get('Location', '')
        match = re.search(r'/NMC/(.+)/logon.htm', location)
        if not match:
            raise Exception("Cannot extract login random value")
        login_num = match.group(1)

        # 登录 POST
        login_url = f"{self.URL_BASE}{login_num}/{self.LOGIN_FORM_URL}"
        login_data = {
            'prefLanguage': '00000000',
            'login_username': self.username,
            'login_password': self.password,
            'submit': 'Log+On'
        }
        resp = self.request_post(login_url, data=login_data)
        location = resp.headers.get('Location', '')
        match = re.search(r'/NMC/(.+)/', location)
        if not match:
            raise Exception("Cannot extract post-login session value")
        session_num = match.group(1)

        self._debug_print(f"Login session number: {session_num}")
        return session_num

    def _ac_operation(self, action_code, ports, pdu_delay=None):
        session_num = self._login()

        # 加载控制页
        outlet_url = f"{self.URL_BASE}{session_num}/{self.OUTLCTRL_URL}"
        self.request_get(outlet_url)

        # 构造控制表单
        outlet_form_url = f"{self.URL_BASE}{session_num}/{self.OUTLCTRL_FORM_URL}"
        outlet_data = {
            'outlet_control_option': action_code,
            'submit': 'Next+>>'
        }
        for port in ports:
            outlet_data.setdefault('OL_Cntrl_Col1_Btn', []).append(f'?{port}')

        # 如果是 reboot_delay 并且指定了延迟秒数
        if action_code == "06000000" and pdu_delay is not None:
            # 这里的字段名称可能因固件不同而异，有的固件叫 'reboot_delay_time'
            outlet_data['reboot_delay_time'] = str(pdu_delay)

        self.request_post(outlet_form_url, data=outlet_data)

        # 应用变更
        apply_url = f"{self.URL_BASE}{session_num}/{self.RPDU_CONF_FORM_URL}"
        apply_data = {'submit': 'Apply'}
        resp = self.request_post(apply_url, data=apply_data)

        return resp

    def ac_reboot_delay(self, ports, pdu_delay=None):
        return self._ac_operation("06000000", ports, pdu_delay)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="APC PDU Power Control Tool (with reboot_delay)")
    parser.add_argument("--ip", required=True, help="PDU IP address")
    parser.add_argument("--ports", required=True,
                        help="Ports list, comma-separated, e.g., 1,2,3")
    parser.add_argument("--action", required=True,
                        choices=["reboot_delay"], help="Action type")
    parser.add_argument("--pdu_delay", type=int, default=None,
                        help="Delay seconds for reboot_delay")
    parser.add_argument("--user", default="apc", help="Login username")
    parser.add_argument("--pwd", default="apc", help="Login password")
    parser.add_argument("--debug", action="store_true",
                        help="Enable debug output")
    args = parser.parse_args()

    ports = [int(p.strip()) for p in args.ports.split(',')]
    controller = APCPDUController(
        args.ip, username=args.user, password=args.pwd, debug=args.debug)

    if args.action == "reboot_delay":
        resp = controller.ac_reboot_delay(ports, args.pdu_delay)
        if resp and (200 <= resp.status_code < 400):
            print(f"[OK] reboot_delay executed successfully on PDU {args.ip} ports {ports} "
                  f"({args.pdu_delay}s delay) (HTTP {resp.status_code})")
        else:
            print(
                f"[WARN] reboot_delay may have been executed. HTTP status: {resp.status_code}")



EOF

}

# 脚本执行等待时间，默认5s，避免部分系统服务启动慢导致的脚本执行时系统服务未就绪引发的异常
sleep 5

# 版本更新日志
function release_version () {
    echo "
    =============================================================
    *   ${PROGRAM_NAME} ${PROGRAM_VERSION}
    *   ${AUTHOR_NAME} ${AUTHOR_NUMBER}
    =============================================================
    Release Note:
    	
		V2.2.2.20250428 jiangqi
		1. [V2.2.2.20250428] Sdx_smartctl_before.log changed to sn_smartctl_before.log,avoid errors caused by drive letter drift.
		
		V2.2.1.20250328 jiangqi
		1. [V2.2.1.20250328] Modify CRACK's black and white list detection tool
		2. [V2.2.1.20250328] Tips for updating CRACK's black and white list detection settings
		
        V2.2.0.20250311 jiangqi
        1. [V2.2.0.20250311] Added check BMC status after entering OS.
        2. [V2.2.0.20250311] Increase SAS and SATA disk speed check

        V2.1.0.20241107 qiaoyu
        1. [V2.1.0.20241107] Fix rc.local is empty maybe error
        2. [V2.1.0.20241107] Support CentOS test
        3. [V2.1.0.20241107] Fix -q log folder name is WarmReboot anyway

        V2.0.1.20230705 caozhiheng

        1. [V2.0.1.20230705] Fix disk error ignore bug
        2. [V2.0.0.20230607] Ignore MDI-X status check by ethtool
        3. [V2.0.0.20230607] Support RHEL9 mcelog and rasdaemon if Service is installed default
        4. [V2.0.0.20230607] Support RC_PATH file is empty or not exist, for RHEL, SLES, Ubuntu series
        5. [V2.0.0.20230607] Fixed special log collect version_id_first is NULL, export xxx not support SubShell var outside FatherShell
        6. [V2.0.0.20230607] Fixed SLES15 or Other Linux Get System Info incorrect because of some service are not ready
        7. [V2.0.0.20230607] ShellCheck format improve, fixed some description issues
        8. [V2.0.0.20230607] Support hooks more styles, such as command, loop, scripts
        9. [V2.0.0.20230607] Support test log name format change: last/times_end + reboot_type(WarmReboot, ColdReboot, DCReboot, NOReboot)
        10.[V2.0.0.20230607] Ignore -t Checking When error Only disk on RHEL9+ OS
        11.[V2.0.0.20230607] Add SCSI ID (Controller HCTL) check, Support HBA Card SLOT check
        12.[V2.0.0.20230607] Fixed disk lost when Serial Number contain special words.

        V1.9.0.20230318 yuxiaonan

        1. [V1.9.0.20230318] Add hooks,allowed user add cmd
        2. [V1.9.0.20230318] Modify -b DCreboot method
        3. [V1.9.0.20230318] Add RC_PATH global variable,value is find_path
     
        V1.8.20230307 wanghongqiang
        1. [V1.8.20230307] envir_config 增加启动NetWorkManager服务；解决网卡up/down问题（详见IDMS单202112270874）

        V1.7.0.20230220 yuxiaonan

        1. [V1.7.0.20230220] Add ethtool check network card
        2. [V1.7.0.20230220] Add SUSE15、ctyunos support
        3. [V1.7.0.20230220] Add port_up_time parameter
        
        v1.6.20230130 wanghongqiang
        1. [v1.6.20230130] 增加CPU型号判断，屏蔽 Hygon BWMgmt+ ABWMgmt- 现象导致的fail问题
        
        V1.5.1.20221206 yuxiaonan
        
        1. [V1.5.1.20221206] Add OpenEuler support
        2. [V1.5.1.20221206] Fixed link state is inconsistent with the actual state.
        
        V1.4.1.20220917 yuxiaonan
        
        1. [V1.4.1.20220917] Add disk serial check

        V1.3.4.20220901 yuxiaonan
        
        1. [V1.3.4.20220901] Fixed reboot_all_log print exception 'mcelog、rasdaemon error' log
        
        V1.3.3.20220824 yuxiaonan
        
        1. [V1.3.3.20220824] Add DC reboot 
        2. [V1.3.3.20220824] Fixed -i times stop dmesg log is empty
        
        V1.3.2.20220816 Caozhiheng
        
        1. [V1.3.0.20220719] Fixed dmesg log is empty 
        2. [V1.3.0.20220719] Add more service check, mcelog and rasdaemon must be enable
        3. [V1.3.0.20220719] Add reboot cancel flag, when AC/DC Test check only
        4. [V1.3.1.20220729] Fixed lsblk get info random disk slot
        5. [V1.3.2.20220816] Fixed -i times will not collect log
        6. [V1.3.2.20220816] Add more failed_type_count type
    
        V1.2.1.20220718 Caozhiheng
        
        1. [V1.2.1.20220718] Fixed Release Note format
        2. [V1.2.1.20220718] Add Example to help, use -h get more
        2. [V1.2.0.20220621] Add NVME U.2 test, -u is added, -s can be suppoted
        3. [V1.2.0.20220621] Add Error Count function
        4. [V1.2.0.20220621] Fixed -s check error
        5. [V1.2.0.20220621] Fixed RTC Time format error
    
        V1.1.0.20220621 Caozhiheng

        1. [V1.1.0.20220621] Support RTC Driver check
        2. [V1.1.0.20220621] Support Reboot directly without waiting for the first time
        3. [V1.1.0.20220621] Support serial port opening function
        4. [V1.1.0.20220621] Support user-defined test times
        5. [V1.1.0.20220621] Add more log collection functions under the OS
        6. [V1.1.0.20220621] Repair dmesg_after log file is empty
        7. [V1.1.0.20220621] Add FC Card test, -f is added, -s can be suppoted
        8. [V1.1.0.20220621] Clear Message and get the new log before reboot
        9. [V1.1.0.20220621] Get more info for CPU and MEM
        10. [V1.1.0.20220621] Fix collect log error
        11. [V1.1.0.20220621] Fix lspci -vvv redirection failed
        
        
        V1.0.0
        
        1. First Version

        "
    exit 0
}

# 错误输出的处理方式
error () {
    echo "$PROGRAM_NAME run with error at $date_time : $1"
    echo "$PROGRAM_NAME run with error at $date_time : $1" >> reboot_all_log
    exit 1
}

# 测试环境配置
envir_config () {
    # echo "Subshell level = $BASH_SUBSHELL"
    find_path
    export RC_PATH
    # [V2.0.0.20230607] 新增RC_PATH统一配置，新建初始模版
    # { 
    #     [ -e "${RC_PATH}" ] && [ -s "${RC_PATH}" ] 
    # } || error "${RC_PATH}  is empty or does not exist, Please Check out...."
    rc_init_files
    # 设置系统语言为英文
    export LANG=en_US.UTF-8
    # 保存主目录
    BASE_DIR=$(pwd)
    export BASE_DIR
    # 添加 rc 文件可执行权限
    chmod +x "${RC_PATH}"
    # 配置 kernlog 日志开关
    sed 's/^#kern\.\*.*/kern\.\*\t\t\t\/var\/log\/kernlog/' -i /etc/rsyslog.conf
    # 配置 mcelog 服务
    mcelog_ser_path=$(find /usr/lib/systemd/ -name 'mcelog.service' -print | xargs -0)
    if [ -n "${mcelog_ser_path}" ] && [ -e "${mcelog_ser_path}" ] && [ -s "${mcelog_ser_path}" ]; then
        sed 's/^ExecStart=.*syslog$/& \-\-logfile=\/var\/log\/mcelog/' -i  "${mcelog_ser_path}"
    fi
    (systemctl start mcelog.service
    systemctl enable mcelog.service
    # 配置rasdaemon服务
    systemctl start rasdaemon.service
    systemctl enable rasdaemon.service
    # 关闭防火墙
    systemctl stop firewalld.service
    systemctl disable firewalld.service) &> /dev/null
    # 开启 RC 服务
    systemctl start rc-local.service
    systemctl status rc-local.service &> /dev/null
    # [V2.0.0.20230607] BUG修复：service状态失败返回0，无法获取准确结论。修正为判断service的实际启用状态。
    # [ "$?" -ne 0 ] && error "rc-local.service is restart failed...."
    if [[ "$(systemctl status rc-local.service| grep -ic "active")" -eq 0 ]]; then
        error "rc-local.service is restart failed...."
    fi
    
    # [V1.8.20230307] envir_config 增加启动NetWorkManager服务，解决网卡up/down问题（详见IDMS单202112270874）
    # 开启 NetworkManager
    systemctl start NetworkManager &> /dev/null
}

# 功能：RC_PATH初始化
# [V2.0.0.20230607] 统一RC_PATH文件，保证开机自启目标存在
# [V2.0.0.20230607] 默认文件结构如下:
# [V2.0.0.20230607] #!/bin/bash
# [V2.0.0.20230607] touch /var/lock/subsys/local
# [V2.0.0.20230607] exit 0
rc_init_files () {
    # RC_PATH文件存在且不能为空
    [ ! -f "${RC_PATH}" ] && mkdir -p "$(dirname "${RC_PATH}")" && touch "${RC_PATH}"
    [ ! -s "${RC_PATH}" ] && echo > "${RC_PATH}"
    
    # RC_PATH首行格式检查
    [ "$(head -n 1 "${RC_PATH}" )" != "#!/bin/bash" ] && sed -i '1i #!/bin/bash' "${RC_PATH}"

    # RC_PATH关键时间戳检查
    [ "$(grep -icwE "touch /var/lock/subsys/local" "${RC_PATH}")" -lt 1 ] && sed -i '2i touch /var/lock/subsys/local' "${RC_PATH}"

    # RC_PATH结束标记exit 0
    [ "$(grep -icwE "exit 0" "${RC_PATH}")" -lt 1 ] && sed -i '$i exit 0' "${RC_PATH}"
}


# 自动判断脚本所处环境，目前支持的系统是RedHat系列，CentOS系列，SUSE12系列，SUSE15系列，CAS系列，Alios系列，欧拉系列，debian系列，OpenEuler系列，天翼云ctyunos。
# 后续支持的系统需求请联系作者
# V1.1.0新增麒麟操作系统，更改error输出为echo输出，解决unknown无法退出的问题。
find_path () {
    # 系统版本号：
    os_version=$(grep -iE "version_id" /etc/os-release | cut -d= -f2 | cut -d '"' -f2)
    
    version_id_first=$(echo "${os_version}" | cut -d '.' -f1)

    # 系统类型名称：centos, rhel, UOS(统信)， ubuntu
    os_type=$(grep -iE "^ID=" /etc/os-release | cut -d= -f2 | cut -d '"' -f2)

    # 系统架构：x86_64
    # architecture=$(uname -m)

    # 通用版本信息
    local all_version
    all_version=$(cat /proc/version)

    # 补充版本信息
    # [V1.5.1.20221206] 适配OpenEuler新增参数
    local special_version
    special_version=$(grep -i name /etc/os-release)
    export os_type_name
    long_rc_local=("red hat" "kylin" "alios" "euleros" "openeuler" "ctyunos" "centos" "uos" "UnionTech OS")
    short_rc_local=("ubuntu" "debian" "deepin" "freebsd")
    boot_rc_local=("suse" )
    # [V1.5.1.20221206] 适配OpenEuler新增判断
    # [V2.0.0.20230607] 修复RHEL系列系统获取信息匹配但超过1的目标场景。
    for cmd in "${long_rc_local[@]}"; do
        if [[ "$(echo "${all_version}" "${special_version}" | grep -ic "${cmd}")" -ne 0 ]]; then
            RC_PATH="/etc/rc.d/rc.local"
            os_type_name="${cmd}" ; return 0
        fi
    done
    for cmd in "${short_rc_local[@]}"; do
        if [[ "$(echo "${all_version}" "${os_type}" | grep -ic "${cmd}")" -ne 0 ]]; then
            RC_PATH="/etc/rc.local"
            os_type_name="${cmd}" ; return 0
        fi
    done
    for cmd in "${boot_rc_local[@]}"; do
        if [[ "$(echo "${all_version}" | grep -ic "${cmd}")" -ne 0 ]]; then
            RC_PATH="/etc/init.d/boot.local"
            os_type_name="${cmd}" ; return 0
        fi
    done
    echo "unknown system"
    return 1
}

# 检查执行bash
judge_sh () {
    bash_path=$(which bash)
    sh_path=$(which sh)
    ret=$?
    if [ "$ret" -eq 0 ]; then
        backup=$(readlink -f "${sh_path}")
        if [[ "$backup" =~ "bash" ]]; then
            echo "sh ----->  ${backup}" >> reboot_all_log
        else
            mv "${sh_path// /}" "${sh_path// /}"_"${backup}"
            ln -s  "${bash_path}" "$(dirname "${bash_path}")"/sh
            chmod 777 "$(dirname "${bash_path}")"/sh
        fi
    else
        ln -s  "${bash_path}" "$(dirname "${bash_path}")"/sh
        chmod 777 "$(dirname "${bash_path}")"/sh
    fi
}

# 1.0.4新增函数，判断是不是root用户
check_user_is_root () {
  username=$(whoami)
  if [ "$username" != "root" ]
  then
    error "must be use root to run $PROGRAM_NAME"
  fi
}

# 1.0.4修复bug,检查目录是否存在
check_dir_exit () {
    test -d "$path" || error "$path is not exit,change the path in $PROGRAM_NAME!"
}

# 1.0.3版本根据反馈结果添加
# 判断用户运行脚本的目录是不是和指定PATH相同,保证能跑Reboot
check_script_exit () {
    test -e "$PROGRAM_NAME" || error "$PROGRAM_NAME is not in $1"
}

# 显示帮助目录菜单
# V1.1.0 更新排版
usage_and_exit () {
echo "
    Usage:
  
    ${PROGRAM_NAME} ${PROGRAM_VERSION} support option is :
  
    -q -n -g -f -s -p -d -e -m -c -b -u -t -v -a -l -o -i number -y -r -k -?
    -q for quit the reboot
    -n for check whether network card whether lost while reboot
    -g for check whether graphics card whether lost while reboot
    -f for check whether FC card whether lost while reboot
    -s check the card speed and status, -n or -g is needed
    -p check all pci device
    -d check disk label and capacity more than 32 GB
    -e for user defined hooks scripts supported
    -m check memory total size whether change while reboot
    -c check cpu core number whether change while reboot
    -b DC reboot (HDM button reboot)
    -u Check NVME U.2/M.2/AIC PCIE Information Whether Change While OS Reboot
    -t whether stop while an error occurred
    -v show $PROGRAM_NAME auther and version
    -l cold reboot (power off then power on)
    -o open system console and redirection
    -i custom reboot times,a space is needed after the follow number!
    -y standby mode instead of soft off (shutdown) , -r -k is not compatible
    -r suspend to ram instead of soft off (shutdown) , -y -k is not compatible
    -k suspend to disk instead of soft off (shutdown) , -r -y is not compatible
    -? show this list
    
    Example:
    
    # 测试参数根据实际测试环境支持情况配置，测试范例参考：
    # 热重启500次，测试出错停止，PCIE类型覆盖：网卡，FC卡，GPU，NVME U.2
    root# sh Cycle_OSReboot.sh –cmdpnfgut -i 500
    # 冷重启500次，测试出错继续，PCIE类型覆盖：网卡，FC卡，GPU，NVME U.2
    root# sh Cycle_OSReboot.sh –cmdpnfgu -l -i 100
    # 网卡模块：热重启200次，测试出错停止
    root# sh Cycle_OSReboot.sh –cmpnst -i 200
    # FC模块：冷重启200次，测试出错停止
    root# sh Cycle_OSReboot.sh –cmpfst -l -i 200
    # GPU模块：冷重启200次，测试出错停止
    root# sh Cycle_OSReboot.sh –cmpgst -l -i 200
    # 硬盘模块：热重启300次，测试出错停止
    root# sh Cycle_OSReboot.sh –cmdt -i 300
    # NVMEU.2模块：冷重启200次，测试出错停止
    root# sh Cycle_OSReboot.sh –cmpust -l -i 200
    # 阵列卡模块：热重启200次，测试出错停止
    root# sh Cycle_OSReboot.sh –cmdpt -i 200
    "
    
    exit 0
}

# 特殊的日志收集
special_collect_log () {
    export logs_path=logs_${date_time}
    mkdir "${logs_path}"
    # dmesg
    dmesg -L > log_of_dmesg
    # mcelog
    # mcelog
    # V1.3.4.20220901 修复reboot_all_log出现异常mcelog、rasdaemon error 日志问题
    # [V2.0.0.20230607] RHEL6+/SLES11+/Ubuntu16+全系列支持开启 mcelog or rasdaemon服务;RHEL6不支持systemctl，Ubuntu系列默认服务未安装
    # [V2.0.0.20230607] 仅支持RHEL7+系列（默认服务已安装）
    if [ "${version_id_first}" -ge 7 ]  && [ "${version_id_first}" -lt 10 ];then
        [ "$(systemctl status mcelog.service | grep -icE "Active.*active.*running")" -gt 0 ] && cat /var/log/mcelog > log_of_mcelog 2> /dev/zero || echo "mcelog.service is not running, Please check!" >> reboot_all_log
        [ "$(systemctl status rasdaemon.service | grep -icE "Active.*active.*running")" -gt 0 ] && ras-mc-ctl --errors > log_of_rasdaemon 2> /dev/zero || echo "rasdaemon.service is not running, Please check!" >> reboot_all_log
    else
        cat /var/log/mcelog > log_of_mcelog 2> /dev/zero
    fi
    # messages
    cp -rf /var/log/messages log_of_messages
    # lspci
    lspci > log_of_lspci 2> /dev/zero
    lspci -vvvxxx >> log_of_lspci 2> /dev/zero
    # dmidecode (实际直接执行就可)
    (dmidecode | grep -i serial
    echo  "*****  Bios "
    dmidecode  -t bios
    echo  "*****  System "
    dmidecode  -t system
    echo  "*****  Baseboard "
    dmidecode  -t baseboard
    echo  "*****  Chassis "
    dmidecode  -t chassis
    echo  "*****  Baseboard "
    dmidecode  -t processor
    echo  "*****  Memory "
    dmidecode  -t memory
    echo  "*****  Cache "
    dmidecode  -t cache
    echo  "*****  Connector "
    dmidecode  -t connector
    echo  "*****  Slot "
    dmidecode  -t slot ) > log_of_dmidecode 2> /dev/zero &
    # lshw
    if [ $lshw_option -eq 0 ]; then
        lshw | grep -i serial > log_of_lshw
        lshw >> log_of_lshw 2> /dev/zero
    fi
    # kernlog
    cat /var/log/kernlog > log_of_kernlog 2> /dev/zero
    # 配置信息
    (echo  "*****  CPU "
    lscpu
    cat /proc/cpuinfo
    echo  "*****  Memery "
    cat /proc/meminfo
    echo  "*****  Storage "
    lsblk
    fdisk -l  2> /dev/zero
    echo  "*****  Network "
    lspci -vvv  2> /dev/null | grep -i ether
    ip a ) > log_of_march_config 2> /dev/zero &
    # 版本信息
    uname -ar > log_of_version
    cat /etc/os-release >> log_of_version
    wait
    # 归档日志文件
    mv log_of*  "${logs_path}"
}

# 获取硬盘scsi上报信息
# 格式示例：
# sd盘符    scsi_id    scsi_slot
# /dev/sda  0:0:0:0     0
# scsi_order
# 打印完整scsi原始顺序
get_disk_scsi_info () {
    lsblk -d -l -o NAME,HCTL |grep -iE "sd.*" > "disk_scsi_$2"
    if [[ "$1" =~ LSI9.00 ]]
    then
        scsi_all=$(grep -iE "scsi.*slot" "dmesg_$2")
        for line in $scsi_all
        do
            scsi_id=$(grep -iE "scsi.*slot" "$line" | sed "s/.*scsi //g" | sed "s/: enclosure.*//g")
            scsi_slot=$(grep -iE "scsi.*slot" "$line" | sed "s/.*scsi.*slot(//g" | sed "s/)//g")
            sed -i "s/${scsi_id}.*/&${scsi_slot}/g" "disk_scsi_$2"
            if [ "$(grep -icE "[0-9]:0:${scsi_slot}:0 .*${scsi_slot}" "disk_scsi_$2")" -ne 1 ]
            then
                sed -i "s/${scsi_id}.*/&    SCSI ERROR/g" "disk_scsi_$2"
            fi
        done
        [ "$(grep -icE "SCSI ERROR" "disk_scsi_$2")" -ne 0 ] && error "Check DISK SCSI FAIL, Please Check disk_scsi_$2." 
    else
        echo "SCSI Info check Only Support LSI9300/9400/9500 Series, Skip!"
    fi
}

# 功能：基准文件，包含基准文件和比较文件，以及两个的全部文件列表
generate_file () {
    # 判断存储文件名的文件是否生成
    file_result=$(cat "genfile_$1" 2> /dev/null)

    # 无条件保留dmesg的信息供查看
    # V1.3.0.20220719 修复dmesg_after为空的问题
    # V1.3.0.20220719 修复shell脚本中dmesg重定向新建失败问题，改用移除文件后新增内容方式重定向，即>改为>>
    rm -rf dmesg_"$1" 2> /dev/null
    dmesg -T >> "dmesg_$1"
    wait
    # V1.3.3.20220824 修复-i参数 dmesg_after为空的问题
    if [ -z "$(cat dmesg_"$1")" ];then
        journalctl -k > dmesg_"$1" 2>&1
    fi

    # [V2.0.0.20230607] 执行用户自定义操作hooks up
    hooks_func "up"

    # 网卡检测
    if [ $network_card -eq 1 ]; then
        local network_bus_li
        network_bus_li=$(lspci | grep -i eth | awk '{print $1}' | xargs)
        lspci | grep -i eth > "network_card_$1" 2> /dev/zero
        printf "\n\n\n\t\t\t\t Network adapter details \n\n" >> "network_card_$1"
        [ $lshw_option -eq 0 ] && lshw -C network | awk 'BEGIN{RS="*-network[:0-9]*"; FS="\n"}{if ($0 ~ "virbr0"){}else {printf $0"\n";}}' | grep -E 'description|product|vendor|bus info|logical name|serial|width|capacity' >> "network_card_$1" 2> /dev/zero
        test -z "$file_result" && echo "network_card_$1" >> "genfile_$1"
        if [ "$1" = "basic" ]
        then
            tmp=$(cat "network_card_$1")
            #V1.1.0 检测到没有网卡先删除日志信息再退出
            #V1.1.1 增加判断语句
            test -z "$network_bus_li"  && collect_log_detect_startup_before_exit "invalid"
            test -z "$network_bus_li" && error "there are not found network_card!"
        fi
        # 网卡速率检测
        if [ $speed -eq 1 ]; then
            for bus_id in  ${network_bus_li}
            do
                echo "$bus_id"
                lspci -vvv -s "$bus_id" 2> /dev/zero | grep -i LnkSta:|awk -F: '{print $2}'|awk -F, '{print $1 $2}'
            done > "network_card_speed_$1"
            #V1.1.0 检测速率的时候同时检测连接状态
            port_name=$(ip link|grep -v -E "virbr|lo"|awk -F: '{if($1 ~ /^[0-9]+/) print $2}'|sort)
                # 添加网口 UP
                #    if [ "$1" == "after" ]; then
                #        sleep 20
                #        dhclient -r
                #        dhclient
                #        for name in $port_name
                #        do
                #            ip link set $name up
                #            sleep 2
                #        done
                #    fi
            # [V1.5.1.20221206] 该sleep是为了避免网口误报UP DOWN状态，若仍存在，可以考虑改长该时间
            if [ ${all_times} -ne 1 ]
            then
                sleep $port_up_time
            fi
            for name in $port_name
            do
                printf "%19s%20s" "$name:"  " Link detected:  "
                #有时会出现误报状态错误
                ip addr show "${name}"  | awk -F 'state' '/state/{print $2}' | awk '{print $1}' | xargs
                # [V1.7.0.20230220] 新增ethtool port_name检查
                # [V2.0.0.20230607] 新增检测忽略MDI-X匹配
                ethtool "$name" | grep -ivE "MDI-X|MDIX" >> "network_card_speed_$1"
            done > "network_card_port_state_$1"
            test -z "$file_result" && echo "network_card_port_state_$1" >> "genfile_$1"
            #v.1.0.7 增加结束
            test -z "$file_result" && echo "network_card_speed_$1" >> "genfile_$1"
        fi
    fi

    # PCI 信息检测
    if [ $pci -eq 1 ]
    then
        echo "" > "pci_speed_$1"
        # [v1.6.20230130] 增加CPU型号判断，若为Hygon,则取消每个设备最后17个字符（BWMgmt+ ABWMgmt-）的打印
        cpu_hygon=$(dmidecode -t processor |grep -c "Hygon")

        for line in $(lspci |awk '{print $1}')
        do
            echo  "$line" >> "pci_speed_$1"

            if [ "$cpu_hygon" -eq 0 ]
            then
            lspci -vvv -s "$line" 2> /dev/null | grep -i width >> "pci_speed_$1"
            else
                lspci -vvv -s "$line" 2> /dev/null | grep -i width |sed '$s/.................$//' >> "pci_speed_$1"
            fi
        
            #sed "$G" -i pci_speed_"$1"
            echo "" >> "pci_speed_$1"
        done
        lspci > "pci_$1"
        test -z "$file_result" && echo "pci_$1" >> "genfile_$1"
        test -z "$file_result" && echo "pci_speed_$1" >> "genfile_$1"
    fi
    
    # V1.1.20220609 NVME 信息检测
    
    if [ $nvme_pcie -eq 1 ]
    then
        lspci | grep -i "Non-Volatile" > "nvme_pcie_$1"
        # lspci | grep -i "controller" > "nvme_pcie_$1"
        test -z "$file_result" && echo "nvme_pcie_$1" >> "genfile_$1"
        if [ "$1" = "basic" ]
            then
            local tmp
            tmp=$(cat "nvme_pcie_$1")
            if [ -z "$tmp" ]
                then
                while read -r files
                do
                    command rm -f "$files"  2> /dev/null
                done < genfile_basic
                collect_log_detect_startup_before_exit "invalid"
                error "there are not found support NVME Disk!"
            fi
        fi
        
        # NVME速率检测
        if [ $speed -eq 1 ]
        then
            while read -r card
            do
                local number
                number=$(echo "$card" | awk '{print $1}')
                echo "$card"
                # lspci -vvv -s $number 2> /dev/null | grep -iE "LnkCap:" |awk -F: '{print $2}'|awk -F, '{print "LnkCap:" $2 $3}'
                lspci -vvv -s "$number" 2> /dev/null | grep -iE "LnkSta:" |awk -v number="$number" -F'[: ,]' '{print number " LnkSta_Speed: " $3 "\n" number " LnkSta_Width: " $6}'
            done < "nvme_pcie_$1" > "nvme_pcie_speed_$1"
            test -z "$file_result" && echo "nvme_pcie_speed_$1" >> "genfile_$1"
        fi
    fi
    
    # 显卡检测
    if [ $graphics_card -eq 1 ]
    then
        lspci | grep -i KONGMING  > "graphics_card_$1"
        test -z "$file_result" && echo "graphics_card_$1" >> "genfile_$1"
        if [ "$1" = "basic" ]
            then
            local tmp
            tmp=$(cat "graphics_card_$1")
            if [ -z "$tmp" ]
                then
                while read -r files
                do
                    command rm -f "$files"  2> /dev/null
                done < genfile_basic
                #V1.1.0 检测到没有显卡先删除日志信息再退出
                collect_log_detect_startup_before_exit "invalid"
                error "there are not found support nvidia graphics_card!"
            fi
        fi
        # 显卡速率检测
        if [ $speed -eq 1 ]
        then
            while read -r card
            do
                local number
                number=$(echo "$card" | awk '{print $1}')
                echo "$card"
                lspci -vvv -s "$number" 2> /dev/null | grep -i LnkSta:|awk -F: '{print $2}'|awk -F, '{print $1 $2}'
            done < "graphics_card_$1" > "graphics_card_speed_$1"
            test -z "$file_result" && echo "graphics_card_speed_$1" >> "genfile_$1"
        fi
    fi

    # FC卡检测
    if [ $fc_card -eq 1 ]
    then
        lspci | grep -iE 'qlogic|emulex' > "fc_card_$1"
        test -z "$file_result" && echo "fc_card_$1" >> "genfile_$1"
        # fc 存在性检测
        if [ "$1" = "basic" ]
        then
            local tmp
            tmp=$(cat "fc_card_$1")
            if [ -z "$tmp" ]
            then
                while read -r files
                do
                    command rm -f "$files"  2> /dev/null
                done < genfile_basic
                #V1.1.0 检测到没有 FC 卡先删除日志信息再退出
                collect_log_detect_startup_before_exit "invalid"
                error "there are not found support FC card!"
            fi
        fi
        # FC 卡速率检测
        if [ $speed -eq 1 ]
        then
            while read -r line
            do
                local BDF
                BDF=$(echo "$line" | awk '{print "0000:"$1}')
                printf "%s\n" "${BDF}"
                hostname=$(ls /sys/bus/pci/devices/"${BDF}" | grep -E "host[0-9]*")
                if [ -z "${hostname}" ]; then
                    continue
                fi
                # 产品名称
                product_name=$(lspci -vvv -s "${BDF}" 2> /dev/zero | grep -E '^[[:space:]]*Subsystem' | awk '{print $4}' | xargs)
                # wwn 号
                port_wwn=$(cat /sys/class/fc_host/"${hostname}"/port_name)
                # 端口 ID
                port_id=$(cat /sys/class/fc_host/"${hostname}"/port_id)
                # 端口状态
                port_state=$(cat /sys/class/fc_host/"${hostname}"/port_state)
                # 端口速率
                port_speed=$(< /sys/class/fc_host/"${hostname}"/speed xargs | sed 's/ //g')
                # 槽位号
                slot_num=$(lspci -vvv -s "${BDF}" 2> /dev/zero | grep -E '^[[:space:]]*Physical Slot' | awk '{print $NF}')
                wait
                printf "%-15s" "$product_name"
                printf "%-20s" "$port_wwn"
                printf "%-10s" "$port_id"
                printf "%-10s" "$port_state"
                printf "%-10s" "$port_speed"
                printf "%-6s\n" "$slot_num"
                wait
            done < "fc_card_$1" > "fc_card_speed_$1"
            test -z "$file_result" && echo "fc_card_speed_$1" >> "genfile_$1"
        fi
    fi

    # 硬盘检测
    if [ $disk_info -eq 1 ]
    then
        # 过滤盘容量在最小规格内大小的盘(G)
        # V1.2.20220620 修复获取磁盘列表存在磁盘容量5位格式无法成功的问题
        # V1.3.0.20220729 新增特性，RHEL8系列lsblk盘符非顺序排列
        # V1.4.1.20220917 新增硬盘乱序检查
        # [V2.0.0.20230607] 新增硬盘scsi HCTL信息检查
        # [V2.0.0.20230607] 修复SN包含非数字母外字符的结果不匹配问题
#        特殊修改前原代码
#        lsblk -d -l -o NAME,SIZE,SERIAL,TYPE | grep -E 'disk$' | sed -n 's/\([a-z0-9]* [.0-9]*\)\([G,T,P] [A-Za-z0-9\.]*\s*disk\)/\1 \2/p' | awk -v num=${min_disk_capa_num} '{if (($3 ~ "G$" && ($2 >= num)) || ($3 ~ "T$|P$"))print}' | sort -u > "disk_$1"
        # 特殊修改，适配nvme盘符乱序
        lsblk_info=$(lsblk -d -l -o NAME,SIZE,SERIAL,TYPE | grep -E 'disk$' | sed -n 's/\([a-z0-9]* [.0-9]*\)\([G,T,P] [A-Za-z0-9\.]*\s*disk\)/\1 \2/p' | awk -v num=${min_disk_capa_num} '{if (($3 ~ "G$" && ($2 >= num)) || ($3 ~ "T$|P$"))print}' | sort -u)
        # 先输出lsblk结果中的首列到待对比文件，按盘符排序
        echo "$lsblk_info" | tr -s ' ' | cut -d ' ' -f1 | sort -k 1 > "disk_$1"
        # 再输出lsblk结果中除去首列的信息到待对比文件，按硬盘序列号排序
        echo "$lsblk_info" | tr -s ' ' | cut -d ' ' -f2- | sort -k 3 >> "disk_$1"
        # 特殊修改，适配nvme盘符乱序
        test -z "$file_result" && echo "disk_$1" >> "genfile_$1"
        if [ "${scsi_info}" -eq 1 ]
        then
            get_disk_scsi_info "${controller}" "$1"
            test -z "$file_result" && echo "disk_scsi_$1" >> "genfile_$1"
        fi
    fi

    # 内存检测
    if [ $memory_size -eq 1 ]
    then
        # 特殊修改前代码
#        free -m | grep -i mem | awk '{ print $2" M" }' > "mem_size_$1"
        # 特殊修改，适配原代码报错内存相差1M的情况。
        # 新方案，-b是bytes单位，允许相差1-999999，忽略后6位数字记录到日志中
        free -b | grep -i mem | awk '{ print int($2/1000000)*1000000" bytes" }' > "mem_size_$1"
        # 特殊修改，适配原代码报错内存相差1M的情况。
        echo "" >> "mem_size_$1"
        dmidecode -t memory | awk 'BEGIN{RS=""; FS="\n"}{if ($5 ~ /Total Width: Unknown/){}else{printf $0"}\n\n"; }}' >> "mem_size_$1"
        test -z "$file_result" && echo "mem_size_$1" >> "genfile_$1"
    fi

    # CPU检测
    if [ $cpu_core -eq 1 ]
    then
        grep -ic processor /proc/cpuinfo > "cpu_core_number_$1"
        echo "" >> "cpu_core_number_$1"
        lscpu | grep -Ev 'CPU MHz|BogoMIPS|Flag'  >> "cpu_core_number_$1"
        test -z "$file_result" && echo "cpu_core_number_$1" >> "genfile_$1"
    fi

    # [V2.0.0.20230607] 执行用户自定义操作hooks down
    hooks_func "down"

    #根据实际情况去判断是否保存PCI的信息或者是disk的信息
    test $pci_command -eq 1 && lspci -vvv 2> /dev/null > "pci_vvv_$1"
    test $disk_command -eq 1 && fdisk -l > "fdisk_l_$1" 2> /dev/null
    test $memory_command -eq 1 && cat /proc/meminfo > "meminfo_$1" 2> /dev/null
    test $cpu_command -eq 1 && cat /proc/cpuinfo > "cpuinfo_$1" 2> /dev/null
}

#错误产生时候的命令日志处理方式，拷贝基准文件，移动当前错误文件
#终止命令下发的命令日志处理方式，移动基准文件和当前错误文件
deal_command_log_files_when_error () {
    if [[ -e genfile_basic ]]
    then
      while read -r files
      do
        if [ "$2" = "cp" ]
        then
            cp "$files" "$1" 2> /dev/null
        else
            mv "$files" "$1" 2> /dev/null
        fi
      done < genfile_basic
    fi

    if [[ -e genfile_after ]]
    then
        while read -r files
        do
            mv "$files" "$1" 2> /dev/null
        done < genfile_after
    fi
}

# 比较生成的文件和基准文件，有错返回非空
compare_file_result () {
    result=
    tmp_detail=
    if [ -e genfile_after ]
    then
        while read -r files
          do
            filename="${files//_after/}"
            # V1.1.20220609 完整输出比较差异信息
            tmp=$(diff "${filename}"_basic "${filename}"_after)
            # V1.1.20220609 当前仅支持nvme，后续支持全部pci设备，且命名统一
            # if [ "$filename" =~ "pci" ] || [ "$filename" =~ "card" ]
            # if [ "$filename" == "nvme_pcie_speed" ]            
            # then
                # diff_list=`cat diff_tmp | awk -F'[ ]' '{print $1}' | sort -u`
                # for nvme_device in $diff_list
                # do
                    # speed_basic=`cat diff_tmp |grep -iE "${nvme_device}.*Speed" |awk '{print $5}' |sed -n '1p'`
                    # speed_after=`cat diff_tmp |grep -iE "${nvme_device}.*Speed" |awk '{print $5}' |sed -n '2p'`
                    # width_basic=`cat diff_tmp |grep -iE "${nvme_device}.*width" |awk '{print $5}' |sed -n '1p'`
                    # width_after=`cat diff_tmp |grep -iE "${nvme_device}.*width" |awk '{print $5}' |sed -n '2p'`
                    # tmp=
                # done
                
            test -n "$tmp" && result="${result} $filename" && tmp_detail="${tmp_detail} ${tmp}"
            
              
          done < genfile_after
    fi
    for files in $(ls "$path/log/$all_times/error")
    do
        tmp="Please check the black and white list error file: $files"
        test -n "$tmp" && result="${result} $files" && tmp_detail="${tmp_detail} ${tmp}"
    done
}

# 第一次跑的时候，手动确认基准文件是否正确
show_basic_file_to_user () {
    if [ -e genfile_basic ]
    then
    while read -r basic
      do
        printf "%s shows that:\n" "$basic"
          cat "$basic"
        printf "\n\n"
      done < genfile_basic

      echo "is all basic is right (Y/N):"
      while read -r input
      do
          if [ "$input" != 'y' ] && [ "$input" != 'Y' ] && [ "$input" != 'n' ] && [ "$input" != 'N' ]
          then
              echo "input error Y/y for right, N/n for error,Input again:"
              continue
          else
              if [ "$input" = 'y' ] || [ "$input" = 'Y' ]
              then
                echo "user confirmed!"
                  break
              else
                # 添加日志收集功能
                special_collect_log
                echo "user ensure basic is error"  >> reboot_all_log
                collect_log_detect_startup_before_exit "invalid"
                exit 1
              fi
          fi
      done
    fi
}

reboot_with_rtc () {
    ctl1='/sys/class/rtc/rtc0/wakealarm'
    ctl2='/proc/acpi/alarm'
    if [ -f "$ctl1" ]
    then
        #V1.1.0 fixed
        #change $(date '+%s' -d "+ $wait_time seconds") to +120 for fix that machine can't wakeup
        wait_time="+$wait_time"
        echo 0 > "$ctl1"
        echo "$wait_time" > "$ctl1"
    elif [ -f "$ctl2" ]
    then
        # V1.2.0.20220621 修复时间格式错误
        wake_time=$(date '+%F %H:%M:%S' -d "+ $wait_time seconds")
        echo "$wake_time" > "$ctl2"
    else
        error "can't do cold reboot in this system"
    fi
    
    check_rtc_driver

    recheck_path=${RC_PATH}
    if [ $standby_state -eq 1 ]
    then
        printf freeze > /sys/power/state
        echo "the $all_times times freeze!"
        sh "$recheck_path"
    fi

    if [ $suspend_mem_state -eq 1 ]
    then
        printf mem > /sys/power/state
        echo "the $all_times times suspend to memory!"
        sh "$recheck_path"
    fi

    if [ $suspend_disk_state -eq 1 ]
    then
        printf disk > /sys/power/state
        echo "the $all_times times suspend to disk"
        sh "$recheck_path"
    fi

    init 0

}

# V1.1.0 增加rtc驱动的检查，用于定位cold reboot的问题
check_rtc_driver () {
    state=$(< /proc/driver/rtc grep -i alarm_IRQ | grep -ic no)
    if [ "$state" -eq  1 ]
    then
        error "rtc doesn't works! please lync $AUTHOR_NAME $AUTHOR_NUMBER"
    fi
    cat /proc/driver/rtc > rtc_debug
    echo "$date_time" >> rtc_debug
}

# 删掉冷重启的项
clear_rtc_setting () {
    ctl1='/sys/class/rtc/rtc0/wakealarm'
    ctl2='/proc/acpi/alarm'
    if [ -f "$ctl1" ]
    then
        echo 0 > "$ctl1"
    elif [ -f "$ctl2" ]
    then
        echo 0 > "$ctl2"
    else
        error "can't clear rtc in this system"
    fi
}
dir_name_smart="smartctl_info"
get_smartctl_info() {
    test_status="$1"
    # 获取服务器上的所有盘符
    devices=$(lsblk -o NAME,TYPE -n -d | grep "disk" | awk '$1 != "loop" {print $1}')
    mkdir -p "$path"/"$dir_name_smart"
    for sdx in $devices; do
        disk_sn=$(smartctl -i /dev/$sdx | grep -i "Serial Number" | awk '{print $NF}')
        smartctl_log_path="$path"/"$dir_name_smart"/"$disk_sn"_smartctl_"$test_status".log
        disk_type=""
        disk_type=$(smartctl -i /dev/$sdx | grep -i "Transport protocol")
        # sas盘可以查询到  Transport protocol: SAS
        # 其他盘查询不到  Transport protocol:
        # 所以如果查询不到Transport protocol: 则为sas盘，否则为STA盘
        echo "" >"$smartctl_log_path"
        if [[ -z "$disk_type" ]]; then
            echo "" >>"$smartctl_log_path"
            echo "cmd: smartctl -i /dev/$sdx" >>"$smartctl_log_path"
            smartctl -i /dev/$sdx | grep -v "Local Time is:" >>"$smartctl_log_path" 2>&1
        else
            echo "" >>"$smartctl_log_path"
            echo "cmd: sg_logs -p 0x18 /dev/$sdx" >>"$smartctl_log_path"
            sg_logs -p 0x18 /dev/$sdx >>"$smartctl_log_path" 2>&1
        fi
    done
}
smartctl_check() {
    # 获取服务器上的所有盘符
    devices=$(lsblk -o NAME,TYPE -n -d | grep "disk" | awk '$1 != "loop" {print $1}')
    mkdir -p "$path"/"$dir_name_smart"
    for sdx in $devices; do
        disk_sn=$(smartctl -i /dev/$sdx | grep -i "Serial Number" | awk '{print $NF}')
        disk_type=""
        disk_type=$(smartctl -i /dev/$sdx | grep -i "Transport protocol")
        # sas盘可以查询到  Transport protocol: SAS
        # 其他盘查询不到  Transport protocol:
        # 所以如果查询不到Transport protocol: 则为sas盘，否则为STA盘
        if [[ -z "$disk_type" ]]; then
            before_speed=$(cat "$path"/"$dir_name_smart"/"$disk_sn"_smartctl_before.log | grep -i 'SATA Version is:' | awk -F current: '{print $NF}')
            after_speed=$(cat "$path"/"$dir_name_smart"/"$disk_sn"_smartctl_after.log | grep -i 'SATA Version is:' | awk -F current: '{print $NF}')
        else
            before_speed=$(cat "$path"/"$dir_name_smart"/"$disk_sn"_smartctl_before.log | grep -i "negotiated logical link rate:")
            after_speed=$(cat "$path"/"$dir_name_smart"/"$disk_sn"_smartctl_after.log | grep -i "negotiated logical link rate:")
        fi
        if [[ "$before_speed" != "$after_speed" ]]; then
            echo "disk: $disk_sn, before: $before_speed, after: $after_speed" >>reboot_all_log
        fi
    done
}

# 退出前收集日志并删除启动项
collect_log_detect_startup_before_exit () {
    name_flag=$1
    filepath=${RC_PATH}
    # V1.1.0 删除多余的``
    sed -i "/^sh.*${PROGRAM_NAME}[^\n]*/"d "$filepath"
    dir_name=${name_flag}_${Stress_Item}_${date_time}

    # V1.1.0 delete `` around below sentence
    mkdir "$dir_name"
    ls $path/smartctl_info/ >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
        get_smartctl_info after
        smartctl_check
        mv ./smartctl_info/ "$dir_name" 2> /dev/null
    fi
    deal_command_log_files_when_error "$dir_name" "mv"
    mv reboot_log reboot_times reboot_all_times dmesg_after reboot_all_log dmesg_basic failed_times succeed_times  "${logs_path}" "$dir_name" 2> /dev/null
    mv rtc_debug  "$dir_name" 2> /dev/null
    mv ./*basic "$dir_name" 2> /dev/null
    mv ./*after "$dir_name" 2> /dev/null
    mv failed_type_count "$dir_name" 2> /dev/null
    # [V1.9.0.20230318] hooks自定义log
    mv hooks_* "$dir_name" 2> /dev/null
}

# V1.1.0 增加判断的条件，和findpath中有重复。
open_console () {
    redhat=$(< /proc/version grep -ic "red hat")
    suse=$(< /proc/version grep -i "suse")
    ubuntu=$(< /proc/version grep -i "ubuntu")
    kylin=$(< /proc/version grep -i "neokylin")
    if [ "$redhat" -eq 1 ] || [ "$kylin" -eq 1 ]
    then
        if [ -f /boot/grub2/grub.cfg ]
        then
            #ensure it is series 7 system
            console_status=$(< /boot/grub2/grub.cfg grep -ic quiet)
            if [ "$console_status" -ne 0 ]
            then
                sed -i "s:rhgb quiet:console=ttyS0,115200n8 console=tty0:" /boot/grub2/grub.cfg
            else
            error "grub has been changed, don't use -o please,action has been canceled!"
            fi
        elif [ -f /boot/grub/grub.conf ]
        then
            #ensure it is series 6 system
            console_status=$(< /boot/grub/grub.conf grep -ic quiet)
            if [ "$console_status" -ne 0 ]
            then
                sed -i "s:rhgb quiet:console=ttyS0,115200n8 console=tty0:" /boot/grub/grub.conf
            else
                error "grub has been changed, don't use -o please,action has been canceled!"
            fi
        elif [ -f /boot/efi/EFI/redhat/grub.conf ]
        then
            #ensure it is series 6 system
            console_status=$(< /boot/efi/EFI/redhat/grub.conf grep -ic quiet)
            if [ "$console_status" -ne 0 ]
            then
                sed -i "s:rhgb quiet:console=ttyS0,115200n8 console=tty0:" /boot/efi/EFI/redhat/grub.conf
            else
                error "grub has been changed, don't use -o please,action has been canceled!"
            fi
        else
                error "can't find grub file in this system,check your configuration"
        fi
    elif [ "$suse" -eq 1 ]
    then
        if [ -f /boot/grub2/grub.cfg ]
        then
            if [ -f /etc/init/ttyS0.conf ]
            then
                error "grub has been changed, don't use -o please,action has been canceled!"
            else
                sed -i 's:GRUB_CMDLINE_LINUX="":GRUB_CMDLINE_LINUX="console=ttyS0,115200n8 console=tty0":' /etc/default/grub
                grub2-mkconfig -o /boot/grub2/grub.cfg
                echo "start on runlevel[23]" > /etc/init/ttyS0.conf
                {
                    echo "stop on runlevel[!23]"
                    echo "respawn"
                    echo "exec /sbin/getty -L 115200 ttyS0 ansi"
                } >> /etc/init/ttyS0.conf
            fi
        elif [ -f /boot/grub/menu.lst ]
        then
            console_status=$(< /boot/grub/menu.lst grep -ic silent)
            if [ "$console_status" -ne 0 ]
            then
                sed -i "s:splash=silent:console=ttyS0,115200n8 console=tty0:" /boot/grub/menu.lst
            else
                error "grub has been changed, don't use -o please,action has been canceled!"
            fi 
        else
            error "can't find grub file in this system,check your configuration"
        fi
    elif [ "$ubuntu" -eq 1 ]
    then
        console_status=$(< /boot/grub/grub.cfg grep -ic quiet)
        if [ "$console_status" -ne 0 ]
        then
            chmod +w /boot/grub/grub.cfg
            sed -i "s:quiet:console=ttyS0,115200n8 console=tty0:" /boot/grub/grub.cfg
        else
            error "grub has been changed, don't use -o please,action has been canceled!"
        fi   
    else
        error "unknown system"
    fi
    echo "open console successful!" >> reboot_all_log
}

reboot_exec () {
    count_log_error
    # V1.1.0 增加判断条件，第一次直接reboot，不等待
    # V1.3.0.20220719 增加重启不执行标记，用于带外控制时系统下信息校验或其他定位场景
    if [ ${reboot_cancel_flag} -eq 1 ]
    then
        echo "Test OK, Please reboot the system by Manual!"
        exit 0
    elif [ ${all_times} -ne 1 ]
    then
        sleep $sleep_time
    fi
    if [ $cold_reboot -eq 1 ]
    then
        reboot_with_rtc
    elif [ $box_use -eq 1 ]; 
    then
		sync
		sleep 3
		echo "AC cycle begin---------"
        if [ $pdu_flag == "1" ];
        then 
                if [ $box_output_port == "A" ]
                then
                ctl_num=10
                poweroff_time="120,0"
                elif [ $box_output_port == "B" ]   
                then
                ctl_num=01
                poweroff_time="0,120"
                else
                ctl_num=11
                poweroff_time="120,120"
                fi
                pwrctl $box_ip $ctl_num $poweroff_time
        elif [ $pdu_flag == "2" ];
        then
        pductl --ip $box_ip --ports $pdu_part --action reboot_delay --pdu_delay 120 
        else
            echo "plsase set pdu_flag=1 or pdu_flag=2 !!"
        fi
    # V1.3.3.20220824新增DC reboot支持
    elif [ $dc_reboot -eq 1 ]
    then
        sync
        sleep 2
        # [V1.9.0.20230318] 优化不需要再输入HDM IP
        ipmitool power cycle
     else
        reboot
    fi
}

clear_os_log () {
    # 清除 messages 日志
    echo "" > /var/log/messages
    # 清楚 kernel 日志
    echo "" > /var/log/kernlog
}

check_system_option_support () {
    if [ "$1" -eq 1 ]
    then
        support_result=$(< /sys/power/state grep -ic "$2")
        if [ "$support_result" -ne 1 ]
        then
            error "you have choose to sleep to $3 mode,but your machine is not support $3 mode in this system! check please!"
        fi
    fi
}

count_log_error () {
    # log_name=`echo $files|sed 's/^\(.*\)_after/\1/'`
    # V1.2.20220622 修复错误日志信息统计识别错误问题
    # v1.3.1.20220729 新增支持错误统计类型
    count_cpu_core_number=$(< reboot_all_log grep -icE "cpu_core_number .*failed")
    count_mem_size=$(< reboot_all_log grep -icE "mem_size .*failed")
    count_disk=$(< reboot_all_log grep -icE "disk .*failed")
    count_pci=$(< reboot_all_log grep -icE "pci .*failed")
    count_pci_speed=$(< reboot_all_log grep -icE "pci_speed .*failed")
    count_nvme_pcie=$(< reboot_all_log grep -icE "nvme_pcie .*failed")
    count_nvme_speed=$(< reboot_all_log grep -icE "nvme_pcie_speed .*failed")
    count_network_card=$(< reboot_all_log grep -icE "network_card .*failed")
    count_network_card_port_state=$(< reboot_all_log grep -icE "network_card_port_state .*failed")
    count_network_card_speed=$(< reboot_all_log grep -icE "network_card_speed .*failed")
    count_graphics_card=$(< reboot_all_log grep -icE "graphics_card .*failed")
    count_graphics_card_speed=$(< reboot_all_log grep -icE "graphics_card_speed .*failed")
    count_fc_card=$(< reboot_all_log grep -icE "fc_card .*failed")
    count_fc_card_speed=$(< reboot_all_log grep -icE "fc_card_speed .*failed")
    echo "OSReboot Error Count:---------------
    CPU CORE NUMBER Error Count:    ${count_cpu_core_number}
    MEM SIZE Error Count:            ${count_mem_size}
    DISK Devices Error Count:        ${count_disk}
    PCI Devices Error Count:         $count_pci
    PCI Devices Speed Error Count:     $count_pci_speed
    NVME PCI Error Count:             $count_nvme_pcie
    NVME Speed Error Count:         $count_nvme_speed
    NIC Devices Error Count:        ${count_network_card}
    NIC Devices Speed Error Count:    ${count_network_card_speed}
    NIC Devices Port State Error Count:    ${count_network_card_port_state}
    GPU Devices Error Count:        ${count_graphics_card}
    GPU Devices Speed Error Count:    ${count_graphics_card_speed}
    FC Devices Error Count:            ${count_fc_card}
    Devices Speed Error Count:        ${count_fc_card_speed}
    " > failed_type_count
}

# hooks_set_up function
hooks_func () {
    if [ "${hooks_command}" -eq 1 ];then
        # (eval '$'"{hooks_set_${1}}")
        local hooks_set="hooks_set_$1" 
        eval "${!hooks_set}"
    fi
}

#当前时间，格式是“年.月.日.时.分.秒”
date_time=$(date +%Y.%m.%d.%H.%M.%S)
# 文件名称
PROGRAM_NAME=$(basename "$0")
# 文件版本号
PROGRAM_VERSION="V2.0.1.20230705"
# 作者名字
AUTHOR_NAME="Caozhiheng"
# 作者工号
AUTHOR_NUMBER="57472"
# 压力测试工具名称
# STRESS_TOOL="Cycle_OSReboot"
Stress_Item="WarmReboot"
#是否进行强制退出的flag
quit_option=0
#是否检查任意pci的flag
pci_command=0
#是否检查任意disk的flag
controller="LSI9361"
disk_command=0
#是否检查任意memory的flag
memory_command=0
#是否检查任意cpu的flag
cpu_command=0
#检查pci速度的flag
speed=0
#检查网卡具体内容的flag
network_card=0
#检查pci全部内容的flag
pci=0
#检查显卡核心的flag
graphics_card=0
#检查nvme设备的flag
nvme_pcie=0
# 检测 fc 卡 flag
fc_card=0
#是否在出错后停止的flag
stop_choice=0
#检查硬盘的信息的flag
disk_info=0
# 盘容量最小规格大小(G)
min_disk_capa_num=32
#检测内存总大小的flag
memory_size=0
#检测CPU核数的flag
cpu_core=0
#选择冷重启还是热重启
cold_reboot=0
#选择冷重启还是热重启
dc_reboot=0
#v1.1.0新增参数
#选择是否开启串口
console_option=0
#是否指定次数
special_time=0
#指定次数的具体值
custom_times=0
#standby状态
standby_state=0
#挂起到内存状态
suspend_mem_state=0
#挂起到硬盘状态
suspend_disk_state=0
# [V1.9.0.20230318] 扩展自定义命令
hooks_command=0
#v1.1.0新增结束
#存储全部选项
all_options=
#存储运行的比较结果
result=
lshw_option=0
# 获取程序绝对路径
path=$(cd "$(dirname "$0")" && pwd || exit)
# RC文件的路径
RC_PATH=

envir_config
#lshw -version &> /dev/null
#[ $? -ne 0 ] && lshw_option=1
if ! lshw -version &> /dev/null;
then
    lshw_option=1
fi

check_user_is_root


#check_dir_exit

cd "${path}" || error "${path} is not exist!Please Check the system environment!"

#check_script_exit $path
#轮询获得所有的参数，有不支持的参数，直接退出
while getopts :eqngfspdtvamcbuloyrki: opt
  do
      case $opt in
    a) box_use=1;box_ip=$box_ip;all_options="$all_options -a";;
    b) dc_reboot=1; all_options="$all_options -b" ;;
    c) cpu_core=1; cpu_command=1; all_options="$all_options -c" ;;
    d) disk_info=1; scsi_info=1; disk_command=1; all_options="$all_options -d" ;;
    e) hooks_command=1; all_options="$all_options -e" ;;
    f) fc_card=1; pci_command=1; all_options="$all_options -f" ;;
    g) graphics_card=1; pci_command=1; all_options="$all_options -g" ;;
    i) special_time=1 ; custom_times=$OPTARG; all_options="$all_options -i $custom_times" ;;
    k) suspend_disk_state=1 ; all_options="$all_options -k" ;;
    l) cold_reboot=1; all_options="$all_options -l" ;;
    m) memory_size=1; memory_command=1; all_options="$all_options -m" ;;
    n) network_card=1; pci_command=1; all_options="$all_options -n" ;;
    o) console_option=1 ;;
    p) pci=1; pci_command=1; all_options="$all_options -p" ;;
    q) quit_option=1; all_options="$all_options -q" ;;
    r) suspend_mem_state=1 ; all_options="$all_options -r" ;;
    s) speed=1; all_options="$all_options -s" ;;
    t) stop_choice=1; all_options="$all_options -t" ;;
    u) nvme_pcie=1; disk_info=1; pci_command=1; disk_command=1; all_options="$all_options -u" ;;
    v) release_version ;;
    y) standby_state=1 ; all_options="$all_options -y" ;;
    '?') usage_and_exit ;;
    ?) error "unsupport option,use -? to see detail" ;;
    esac
  done
shift $((OPTIND -1))
test $# -ne 0 && error "use -$1 not a single $1 please,check your option."
# 只选测速度，但是没有选网卡速度还是显卡速度，错误退出
# V1.1.20220609 增加nvme_pcie标记，判断方式简单化
# if [ $speed -eq 1 -a $network_card -eq 0 ] && [ $speed -eq 1 -a $graphics_card -eq 0 ] && [ $speed -eq 1 -a $fc_card -eq 0 ]
if [ $speed -eq 1 ] && [ $((network_card + graphics_card + fc_card + nvme_pcie)) -eq 0 ]
then
    error "-s means check speed need to -n or -g or -f option"
fi
# V1.1.0检查次数输入是否有问题
custom_result=$(echo "$custom_times" | awk '{if ($0 ~ /^[0-9]+$/) print "1"; else print "0";}')
if [ "$custom_result" -eq 0 ]
then
    error "user define reboot times not a number! check please!"
fi
# V1.1.0 检查y r k参数是不是输出多了
# 检查y r k 参数存在，则自动增加-l 参数
suspend_tmp_result=$((standby_state+suspend_mem_state+suspend_disk_state))
if [ $suspend_tmp_result -gt 1 ]
then
    error "option -y -r -k is only one allow!"
elif [ $suspend_tmp_result -eq 1 ] && [ $cold_reboot -eq 0 ]
then
    cold_reboot=1
    all_options="$all_options -l"
fi
# 设置了参数，检查系统支持情况
check_system_option_support $standby_state "freeze" "S1 (standby)"
check_system_option_support $suspend_mem_state "mem" "S3 (suspend to ram)"
check_system_option_support $suspend_disk_state "disk" "S4 (suspend to disk)"

#V1.1.0要求打开系统下的串口
if [ "$console_option" -eq 1 ]
then
    open_console
fi

[ "$cold_reboot" -eq 1 ] && Stress_Item="ColdReboot"
[ "$dc_reboot" -eq 1 ] && Stress_Item="DCReboot"
[ "$reboot_cancel_flag" -eq 1 ] && Stress_Item="NOReboot"

# V1.1.0结束
# reboot_all_times：本次reboot的所有日志记录
touch reboot_all_times
all_times=$(cat reboot_all_times)
all_times=$((all_times+1))
# reboot_times记录上一次出错到下一次出错的次数
touch reboot_times
times=$(cat reboot_times)
times=$((times+1))
# 判断第一次操作还是非第一次操作
if [ $all_times -eq 1 ]
then
    judge_sh
    # 如果第一次操作就有-q选项，那么就报错。
    if [ $quit_option -eq 1 ]
    then 
        error "Loop is not start,Please don't use -q "
    fi
    #V1.1.0提前一点，先判断系统是否满足再生成BASIC
    #获得系统信息并修改启动项
    filepath=${RC_PATH}

    #V1.1.0 增加对Path的判断
    if [ "$(grep -ic "unknown" "$filepath")" -ne 0 ]
    then
        error "unknown system, lync $AUTHOR_NAME $AUTHOR_NUMBER to get help!"
    fi
    #生成basic文件
    generate_file "basic"
    #手动确认基准文件是否正确
    show_basic_file_to_user
    if [ "$scsi_info" -eq 1 ]
    then
        get_smartctl_info before
    fi
    #V1.1.0 更改关键字reboot为变量名，增加灵活性
    # [V2.0.0.20230607] 统一RC_PATH处理方式，模版格式（声明解释器+touch时钟+Cycle命令+exit0）
    # [V2.0.0.20230607] 优化启动项格式，exit 0行首删除空格。
    sed -i "/^sh.*$PROGRAM_NAME*/"d "$filepath"
    #if [ "$filepath" = "/etc/rc.local" ] 
    #then
    # [V2.0.0.20230607] 命令解释：启动项在exit 0前插入一行执行命令，\&后台执行，&保留匹配exit 0
    sed -i "s:[^\n]*exit 0[^\n]*:sh $path/$PROGRAM_NAME $all_options \&\n&:" "$filepath"
    # else
    #     echo "sh $path/$PROGRAM_NAME $all_options &" >> "$filepath"
    #fi
    chmod 777 "$filepath"
    echo "you are now entering a ${Stress_Item} loop,wait for first ${Stress_Item}."
    # 完善黑白名单筛选列表
    bash "$path"/add_white_black.sh -s "$server_type" -g "$gen"
else
    #有-q命令的时候，移除所有的log，并杀掉reboot进程，而且删除启动项。
    if [ $quit_option -eq 1 ]
    then
        # [V2.0.0.20230607] pgrep获取进程列表需移除自身PID，否则会终止退出异常
        v_pid=$BASHPID
        pgrep -f "${PROGRAM_NAME}" | grep -v $v_pid | xargs kill
        clear_rtc_setting
        # 添加日志收集功能
        special_collect_log
        generate_file "after"
		is_cold_reboot=$(grep -icE "sh $path/${PROGRAM_NAME}.*\-l" "${RC_PATH}")
        is_dc_reboot=$(grep -icE "sh $path/${PROGRAM_NAME}.*\-b" "${RC_PATH}")
        [ "${is_cold_reboot}" == 1 ] && Stress_Item="ColdReboot"
        [ "${is_dc_reboot}" == 1 ] && Stress_Item="DCReboot"
        collect_log_detect_startup_before_exit "last"
        wait
        echo "the loop has been stop!"
        exit 0
    fi
    ls $path/smartctl_info/ >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
        get_smartctl_info after
        smartctl_check
        mv ./smartctl_info/ "$dir_name" 2> /dev/null
    fi
    white_black_info=$(bash ./check_server_zijie_h3c.sh 2>&1)
    if [[ "$white_black_info" == *"error"* ]]; then
        echo "the $all_times times white black check an error occurred" >> "log/white_black_log.txt"
    elif [[ "$white_black_info" == *"Error"* ]]; then
        echo "the $all_times times white black check an error occurred" >> "log/white_black_log.txt"
    else
        echo "the $all_times times white black check with no error" >> "log/white_black_log.txt"
    fi
    # 防止 有的机器反应慢
    sleep ${react_time}
    # 生成after文件
    generate_file "after"
    # 对比basic和after文件
    compare_file_result
fi
echo $all_times > reboot_all_times
echo $times > reboot_times
if [ -z "$result" ] 
then
    #没有错误的时候的处理方式，succeed次数加1
    touch succeed_times
    succeed=$(cat succeed_times)
    succeed=$((succeed+1))
    echo $succeed > succeed_times
    #处理第一次运行的特殊情况
    if [ $all_times -eq 1 ]
    then
        echo "the 1 times ${Stress_Item} at $date_time with option $all_options aim to generate basic file. StressTool Version: ${PROGRAM_VERSION}" >> reboot_all_log
    else
        echo "the $all_times times ${Stress_Item} at $date_time with no error" >> reboot_all_log
    fi
    echo "the $times times ${Stress_Item} at $date_time with no error" >> reboot_log
else
    echo "reboot error occurred"
    #出错的时候的处理方式，failed次数加1
    touch failed_times
    failed=$(cat failed_times)
    failed=$((failed+1))
    echo $failed > failed_times
    #处理出错的日志
    echo -e "the $all_times times ${Stress_Item} at $date_time , an error occurred:check $result failed, Please Check! \n $tmp_detail " >> reboot_all_log
    echo -e "the $times times ${Stress_Item} at $date_time , an error occurred:check $result failed, Please Check! \n $tmp_detail  " >> reboot_log
    dir_name=err_env_$date_time
    mkdir "$dir_name"
    deal_command_log_files_when_error "$dir_name" "cp"
    mv reboot_log reboot_times  dmesg_after "$dir_name" 2> /dev/null
    cp reboot_all_log dmesg_basic "$dir_name" 2> /dev/null
    #如果此次运行和PCI有关则保留PCI相关信息
    if [ $pci_command -eq 1 ]
    then
        mv pci_vvv_after "$dir_name" 2> /dev/null
        mv pci_speed_after "$dir_name" 2> /dev/null
        cp pci_vvv_basic "$dir_name" 2> /dev/null
        cp pci_speed_basic "$dir_name" 2> /dev/null
    fi
    #如果此次运行和DISK有关则保留DISK相关信息
    if [ $disk_command -eq 1 ]
    then
        mv fdisk_l_after "$dir_name" 2> /dev/null
        cp fdisk_l_basic "$dir_name" 2> /dev/null
    fi
    #如果此次运行和CPU有关则保留CPU相关信息
    if [ $cpu_command -eq 1 ]
    then
        mv cpuinfo_after "$dir_name" 2> /dev/null
        cp cpuinfo_basic "$dir_name" 2> /dev/null
    fi
    #如果此次运行和Memory有关则保留Memory相关信息
    if [ $memory_command -eq 1 ]
    then
        mv meminfo_after "$dir_name" 2> /dev/null
        cp meminfo_basic "$dir_name" 2> /dev/null
    fi
    # [V1.9.0.20230318] 如果此次运行和hooks有关，保留hooks相关log
    if [ $hooks_command -eq 1 ]
    then
        mv hooks_* "$dir_name"
    fi
    
    #如果选项设置了出错即停止，则退出不再reboot
    if [ $stop_choice -eq 1 ]
    then
        # [V2.0.0.20230607] RHEL9+忽略仅发生disk盘符错误时的错误停止场景
        # [V2.0.1.20230705] 修复过滤规则错误
        if [ -z "${result//disk}" ] && [ "${os_type}" == "rhel" ] && [ "${version_id_first}" -ge 9 ]
        then
            echo "Ignore Error: RHEL 9+ disk error Only, Please Check it, Test Continued!" >> reboot_all_log
        else
            special_collect_log
            collect_log_detect_startup_before_exit "error"
            exit 0
        fi
    fi
fi

hdm_ip=$(ipmitool lan print | grep -i 'IP Address' | grep -v 'IP Address Source' | awk -F : '{print $NF}')
hdm_power_status=$(ipmitool -I lanplus -H $hdm_ip -U admin -P Password@_ power status)
if [[ "$hdm_power_status" != *"Chassis Power is on"* ]]; then
    echo "the $all_times reboot, hdm power off" >>reboot_all_log 2>&1
fi

# 清除旧的日志
clear_os_log

#V1.1.0 增加用户限制次数
if [ "$special_time" -eq 1 ]
then
    if [ "$all_times" -lt "$custom_times" ]
    then
        reboot_exec
    else
        echo "we has run $custom_times times reboot and stop reboot automaticly" >> reboot_all_log
#        generate_file "after"
        special_collect_log
        collect_log_detect_startup_before_exit "times_end"
    fi
else
    reboot_exec
fi

