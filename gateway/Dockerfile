FROM openresty/openresty:alpine-fat

RUN luarocks install pgmoon && \
    luarocks install lua-resty-http && \
    luarocks install lua-resty-mail && \
    apk add --no-cache postgresql-client curl

COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY lua/ /usr/local/openresty/nginx/lua/
COPY panel/ /usr/local/openresty/nginx/panel/

EXPOSE 80

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
