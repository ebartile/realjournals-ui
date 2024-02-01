FROM nginx

COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d /etc/nginx/conf.d
COPY templates /etc/nginx/templates
COPY includes /etc/nginx/includes

RUN touch /var/log/nginx/error.log
RUN touch /var/log/nginx/access.log
RUN chown nginx:nginx /var/log/nginx/error.log
RUN chown nginx:nginx /var/log/nginx/access.log

EXPOSE 80
EXPOSE 443