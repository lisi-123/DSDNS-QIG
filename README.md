# DSDNS - 智能地理 DNS 服务

DSDNS 是一个基于 GeoIP 的智能 DNS 解析系统，支持根据用户地理位置（国家、运营商、省份/城市）返回不同的 DNS 解析结果。支持 A、AAAA、CNAME 记录类型，提供 Web 管理界面。

## 功能特性

- 🌍 智能解析：根据用户 IP 地理位置返回最优解析结果
- 🚀 高性能：基于 ip2region 离线库，毫秒级地理定位
- 🗂️ 灵活规则：支持大洲、国家、运营商、省份/城市模糊匹配
- 🔐 用户认证：JWT 身份验证，支持管理员和普通用户
- 🖥️ Web 管理：可视化 DNS 记录管理界面
- 📦 轻量部署：单二进制文件，无需外部依赖

## 快速安装（推荐）

使用一键安装脚本，自动完成下载、解压和配置：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lisi-123/DSDNS-QIG/main/install.sh)"

```

安装后，项目文件在 /opt/dsdns ，包括可执行文件，配置文件以及 sqlite文件

访问 `http://vps的ip:8053` 打开控制面板

默认没有开启tls，有需要自己装nginx反代


## 端口转发

转发 UDP 和 TCP 的 53 端口到 5353，并保存iptables规则
config.yaml 默认使用5353，如果需要使用其他端口，请自行修改

```bash
iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-port 5353
iptables -t nat -A PREROUTING -p tcp --dport 53 -j REDIRECT --to-port 5353
apt install iptables-persistent -y
netfilter-persistent save

```


## 使用方法

假设vps的ip是 11.22.33.44

假设你有一个域名 example.com 


### 1.创建ns域名

创建 ns1.example.com 的a记录，解析 11.22.33.44

创建 ns2.example.com 的a记录，解析 11.22.33.44


### 2.托管域名到DSDNS

假设要托管 dsdns.example.com (或其他你控制的域名都可以)

做两个ns记录 

<br>

———————————————————————————————————————


  &emsp;&emsp;&emsp;     名称    &emsp;&emsp;&emsp;&emsp;       类型     &emsp;&emsp;&emsp;&emsp;     内容

dsdns.example.com   &emsp;  NS   &emsp;&emsp;  ns1.example.com

dsdns.example.com   &emsp;  NS   &emsp;&emsp;  ns2.example.com


———————————————————————————————————————

<br>

做完就相当于把  dsdns.example.com 托管到自建的 DSDNS 系统了

接下来去 DSDNS 里添加 dsdns.example.com ，并添加a，aaaa或cname记录，就可以生效了


如果要填写 中国大陆 的 “省/市” 字段，注意填写规则：

北京市填写 北京 ，重庆市填写 重庆 ，四川省填写 四川 ，江苏省填写 江苏 ，依此类推





<br><br><br>





