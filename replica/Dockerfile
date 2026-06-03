FROM postgres:16

COPY init-replica.sh /init-replica.sh
RUN chmod +x /init-replica.sh

ENTRYPOINT ["/init-replica.sh"]
CMD ["postgres"]
