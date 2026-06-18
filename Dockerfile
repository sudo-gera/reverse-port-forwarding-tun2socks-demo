FROM --platform=linux/amd64 ubuntu@sha256:4e0171b9275e12d375863f2b3ae9ce00a4c53ddda176bd55868df97ac6f21a6e
RUN apt update && apt install -y curl wget
RUN apt install -y inetutils-ping microsocks unzip tar xz-utils iproute2 jq

COPY <<"EOF" downloader.sh
#!/usr/bin/env bash
set -xeu

name_to_save="$1"
name_to_download="$2"

ru_prefix='https://gitflic.ru/project/sudogera/files/blob/raw?inline=false&commit=6db75e9f9aef0a740edc88d73a455354ede569af&file='
us_prefix='https://github.com/sudo-gera/files/raw/refs/heads/master/'

ipinfo="$(curl https://ipinfo.io  --resolve ipinfo.io:443:34.117.59.81)"
echo "$ipinfo" | jq

if echo "$ipinfo" | jq -e '.country == "RU"'
then
    curl -Lo "${name_to_save}" "${ru_prefix}${name_to_download}"
else
    curl -Lo "${name_to_save}" "${us_prefix}${name_to_download}"
fi
EOF
RUN chmod +x downloader.sh

RUN ./downloader.sh curl.tar curl-linux-x86_64-musl-8.16.0.tar.xz
RUN ./downloader.sh reverse_tcp_forwarding reverse_tcp_forwarding
RUN ./downloader.sh badvpn-udpgw badvpn-udpgw
RUN ./downloader.sh badvpn-tun2socks badvpn-tun2socks

RUN echo reverse_tcp_forwarding.txt > reverse_tcp_forwarding.txt
RUN tar -xf ./curl.tar

COPY <<"EOF" enable_tun2socks_ifaces.sh
ip tuntap add dev badvpntun mode tun
ip addr add 10.240.128.1/30 dev badvpntun
ip link set badvpntun up
ip route add 0.0.0.0/1 via 10.240.128.2 dev badvpntun
ip route add 128.0.0.0/1 via 10.240.128.2 dev badvpntun
EOF

COPY <<"EOF" disable_tun2socks_ifaces.sh
ip route del 0.0.0.0/1 via 10.240.128.2 dev badvpntun
ip route del 128.0.0.0/1 via 10.240.128.2 dev badvpntun
ip link set badvpntun down
ip tuntap del dev badvpntun mode tun
EOF

RUN chmod +x enable_tun2socks_ifaces.sh disable_tun2socks_ifaces.sh reverse_tcp_forwarding badvpn-udpgw badvpn-tun2socks
