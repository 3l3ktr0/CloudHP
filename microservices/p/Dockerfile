FROM tiangolo/uwsgi-nginx-flask:flask-python3.5
RUN pip3 install requests python-swiftclient python-keystoneclient
ADD . /app
WORKDIR /app
