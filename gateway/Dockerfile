FROM openresty/openresty:alpine-fat

RUN luarocks install pgmoon && \
    luarocks install lua-resty-http && \
    apk add --no-cache postgresql-client

COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY lua/ /usr/local/openresty/nginx/lua/
COPY panel/ /usr/local/openresty/nginx/panel/

EXPOSE 80

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
