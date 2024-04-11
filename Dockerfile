FROM scratch
COPY --from=qemux/qemu-docker:4.20 / /

COPY ./src /run/

RUN chmod +x /run/*.sh

EXPOSE 8006 3389

ENV RAM_SIZE "4G"
ENV CPU_CORES "4"
ENV DISK_SIZE "64G"
ENV VERSION "deepin"

ARG VERSION_ARG "0.0"
RUN echo "$VERSION_ARG" > /run/version

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]