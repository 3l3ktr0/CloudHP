FROM python:3.4-alpine
ADD . /b
WORKDIR /b
RUN pip3 install flask requests python-swiftclient
EXPOSE 5003
CMD ["python", "b.py"]
