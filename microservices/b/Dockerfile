FROM tiangolo/uwsgi-nginx-flask:flask-python3.5
RUN pip3 install requests python-swiftclient python-keystoneclient
RUN pip3 install pymysql
ADD . /app
WORKDIR /app
