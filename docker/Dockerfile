FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    sudo \
    nano \
    curl \
    lsb-release \
    gnupg2 \
    iputils-ping \
    net-tools \
    iproute2 \
    ca-certificates \
    tcpdump \
    traceroute

# FRR

RUN curl -s https://deb.frrouting.org/frr/keys.gpg | tee /usr/share/keyrings/frrouting.gpg > /dev/null

ARG FRRVER="frr-10"

RUN echo "deb [signed-by=/usr/share/keyrings/frrouting.gpg] https://deb.frrouting.org/frr $(lsb_release -s -c) $FRRVER" | tee /etc/apt/sources.list.d/frr.list

RUN apt-get update && apt-get install -y \
    frr \
    frr-pythontools

COPY frr-restart.sh /usr/local/bin/frr-restart
RUN chmod +x /usr/local/bin/frr-restart

COPY configs/ /etc/frr/hosts/

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

CMD ["/usr/local/bin/entrypoint.sh"]
