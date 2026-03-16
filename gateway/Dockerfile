FROM openresty/openresty:alpine-fat

RUN luarocks install pgmoon && \
    luarocks install lua-resty-http && \
    luarocks install lua-resty-mail && \
    apk add --no-cache postgresql-client curl ca-certificates && \
    update-ca-certificates

COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY lua/ /usr/local/openresty/nginx/lua/
COPY panel/ /usr/local/openresty/nginx/panel/

# Bundle QR code library locally (MIT license) — no external deps at runtime
RUN curl -sL "https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js" \
    -o /usr/local/openresty/nginx/panel/js/qrcode.min.js

EXPOSE 80

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
