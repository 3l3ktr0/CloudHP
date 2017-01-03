FROM python:3.4-alpine
ADD . /i
WORKDIR /i
RUN pip install flask pymysql
EXPOSE 5001
CMD ["python", "i.py"]
