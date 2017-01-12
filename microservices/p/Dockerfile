FROM python:3.4-alpine
ADD . /p
WORKDIR /p
RUN pip3 install flask requests python-swiftclient
EXPOSE 5004
CMD ["python", "p.py"]
