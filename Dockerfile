FROM rockylinux:9.3-minimal

WORKDIR /tmp

# Install prerequisites for Nginx compile
RUN microdnf update -y && microdnf install -y \
        wget \
        tar \
        openssl-devel \
        gcc \
        gcc-c++ \
        make \
        zlib-devel \
        pcre-devel \
        gd-devel \
        git

# Download Nginx and Nginx modules source
RUN wget http://nginx.org/download/nginx-1.25.5.tar.gz -O nginx.tar.gz && \
    mkdir /tmp/nginx && \
    tar -xzvf nginx.tar.gz -C /tmp/nginx --strip-components=1

# Build Nginx
WORKDIR /tmp/nginx
RUN ./configure \
        --user=nginx \
        --group=nginx \
        --prefix=/usr/share/nginx \
        --sbin-path=/usr/sbin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --pid-path=/run/nginx.pid \
        --lock-path=/run/lock/subsys/nginx \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --with-http_gzip_static_module \
        --with-http_stub_status_module \
        --with-http_ssl_module \
        --with-pcre \
        --with-file-aio \
        --with-http_gunzip_module && \
    make && \
    make install


# Cleanup after Nginx build
RUN yum remove -y \
        wget \
        tar \
        gcc \
        gcc-c++ \
        make \
        git && \
    yum autoremove -y && \
    rm -rf /tmp/*

# Configure filesystem to support running Nginx
RUN adduser -c "Nginx user" nginx && \
    setcap cap_net_bind_service=ep /usr/sbin/nginx

# Apply Nginx configuration
ADD config/nginx.conf /etc/nginx/nginx.conf

# This script gets the linked PHP-FPM container's IP and puts it into
# the upstream definition in the /etc/nginx/nginx.conf file, after which
# it launches Nginx.
ADD config/nginx-start.sh /opt/bin/nginx-start.sh
RUN chmod u=rwx /opt/bin/nginx-start.sh && \
    chown nginx:nginx /opt/bin/nginx-start.sh /etc/nginx /etc/nginx/nginx.conf /var/log/nginx /usr/share/nginx

# DATA VOLUMES
RUN mkdir -p /data/nginx/www/
RUN mkdir -p /data/nginx/config/
VOLUME ["/data/nginx/www"]
VOLUME ["/data/nginx/config"]

# PORTS
EXPOSE 80
EXPOSE 443

USER nginx
ENTRYPOINT ["/opt/bin/nginx-start.sh"]
