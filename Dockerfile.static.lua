FROM debian:stable-slim

ARG NGINX_VERSION=1.25.5
ARG OPENSSL_VERSION=3.4.0
ARG ZLIB_VERSION=1.3.1
ARG LUAJIT2_VERSION=2.1-20241113
ARG NGX_DEVEL_KIT_VERSION=0.3.3
ARG LUA_NGINX_MODULE_VERSION=0.10.27
ARG LUA_RESTY_CORE_VERSION=0.1.30
ARG LUA_RESTY_LRUCACHE_VERSION=0.15
ARG NGINX_OTEL_VERSION=0.1.1
ARG ABSEIL_VERSION=20211102.0
ARG GRPC_VERSION=1.46.7
ARG OPENTELEMETRY_CPP_VERSION=1.18.0
ARG OPENTELEMETRY_PROTO_VERSION=1.4.0
ARG PROTOBUF_VERSION=3.19.5

ARG DEBIAN_FRONTEND=noninteractive
ARG ROOT_DIR=/tmp/build
ARG GITHUB=https://github.com
ARG CMAKE_COMMON="-DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_EXTENSIONS=OFF \
  -DCMAKE_CXX_VISIBILITY_PRESET=hidden -DCMAKE_POLICY_DEFAULT_CMP0063=NEW \
  -DCMAKE_PREFIX_PATH=${ROOT_DIR}/ -DCMAKE_INSTALL_PREFIX:STRING=${ROOT_DIR}/ \
  -DCMAKE_INSTALL_LIBDIR:STRING=lib -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo"

WORKDIR /tmp

RUN apt update -y && apt -y upgrade && apt -y install curl gcc make perl libc6-dev libxslt1-dev libxml2-dev \
      zlib1g-dev libpcre3-dev libbz2-dev libssl-dev

RUN curl http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar xzf - && mv nginx-${NGINX_VERSION} nginx && \
  curl -L ${GITHUB}/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz | tar xzf - && \
  curl -L http://zlib.net/zlib-${ZLIB_VERSION}.tar.gz | tar xzf - && \
  curl -L ${GITHUB}/openresty/luajit2/archive/refs/tags/v${LUAJIT2_VERSION}.tar.gz | tar xzf - && \
  curl -L ${GITHUB}/vision5/ngx_devel_kit/archive/refs/tags/v${NGX_DEVEL_KIT_VERSION}.tar.gz | tar xzf - && \
  curl -L ${GITHUB}/openresty/lua-nginx-module/archive/refs/tags/v${LUA_NGINX_MODULE_VERSION}.tar.gz | tar xzf - && \
  curl -L ${GITHUB}/openresty/lua-resty-core/archive/refs/tags/v${LUA_RESTY_CORE_VERSION}.tar.gz | tar xzf - && \
  curl -L ${GITHUB}/openresty/lua-resty-lrucache/archive/refs/tags/v${LUA_RESTY_LRUCACHE_VERSION}.tar.gz | tar xzf -

# You can also change the installation directory to any other directory you like with the LUA_LIB_DIR argument.
## cd lua-resty-core; sudo make install LUA_LIB_DIR=/opt/nginx/lualib
# After that, you need to add the above directory to the LuaJIT search direcotries with lua_package_path nginx directive in the http context and stream context.
## lua_package_path "/opt/nginx/lualib/?.lua;;";

# configure - this configuration enables every possible module, except:
# 1) --with-cpp_test_module --with-google_perftools_module
#    Not needed for production build.
# 2) --with-http_xslt_module --with-http_image_filter_module --with-http_geoip_module
#    Requires additional modules to be built from sources, or symlinked to proper paths as configure lookups those in /usr/local, /usr/pkg and /opt/local.
# 3) --with-http_perl_module
#    Perl needs to be built from source, as Debian's pkg does not deliver static library.
# Setting --prefix to /opt/nginx results in nginx by default:
#  1) logging to /opt/nginx/logs/error.log 
#  2) reading cfg file from /opt/nginx/conf/nginx.conf

RUN cd luajit2-${LUAJIT2_VERSION} && DESTDIR=${ROOT_DIR} CFLAGS="-fPIC" make install 

RUN export USE_LUAJIT=1 && \
    export LUAJIT_LIB=${ROOT_DIR}/usr/local/lib && \
    export LUAJIT_INC=${ROOT_DIR}/usr/local/include/luajit-2.1 && \
    cd nginx && \
    ./configure \
    --conf-path=nginx.conf \
    --error-log-path=logs/error.log \
    --http-client-body-temp-path=tmp/client_body_temp/ \
    --http-proxy-temp-path=tmp/proxy_temp/ \
    --pid-path=nginx.pid \
    --prefix=. \
    --sbin-path=. \
    --with-cc-opt='-static -static-libgcc -DTCP_FASTOPEN=23' \
    --with-cpu-opt=generic \
    --with-file-aio \
    --with-http_gzip_static_module \
    --with-http_realip_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-ld-opt="-static -Wl,-rpath,${LUAJIT_LIB}" \
    --add-module=../ngx_devel_kit-${NGX_DEVEL_KIT_VERSION} \
    --add-module=../lua-nginx-module-${LUA_NGINX_MODULE_VERSION} \
    --with-openssl=../openssl-${OPENSSL_VERSION} \
    --with-pcre \
    --with-pcre-jit \
    --with-threads \
    --with-zlib=../zlib-${ZLIB_VERSION} \
    --without-http_fastcgi_module \
    --without-http_scgi_module \
    --without-http_uwsgi_module && \
    make -j1 && \
    make -j1 install && \
    tar cfvz ../nginx-static.tgz nginx nginx.conf logs && \
    ./nginx -V && ls -l ./nginx

#  --prefix=nginx-static \
#  --with-cc-opt="-static -static-libgcc" \
#  --with-ld-opt="-static" --with-cpu-opt=generic --with-pcre \
#  --with-select_module --with-poll_module \
#  --with-http_ssl_module --with-http_realip_module \
#  --with-http_addition_module --with-http_sub_module \
#  --with-http_gunzip_module \
#  --with-http_gzip_static_module --with-http_auth_request_module \
#  --with-http_random_index_module --with-http_secure_link_module \
#  --with-http_degradation_module --with-http_stub_status_module \
#  --with-openssl=../openssl-${OPENSSL_VERSION} && \
# with -j > 1 nginx's tries to link openssl before it gets built

RUN ldd /tmp/nginx/nginx || true

FROM scratch
COPY --from=0 /tmp/nginx/nginx /tmp/nginx/nginx.conf /tmp/nginx/logs /nginx/
WORKDIR /nginx
