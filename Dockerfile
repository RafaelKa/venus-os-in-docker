FROM scratch
COPY .ext4.mount/ /
ENTRYPOINT ["/bin/bash"]