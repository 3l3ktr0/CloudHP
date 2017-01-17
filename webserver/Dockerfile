FROM tiangolo/uwsgi-nginx-flask:flask-python3.5
RUN pip install requests
COPY ./app /app
COPY ./nginx.conf /etc/nginx/conf.d
WORKDIR /app
