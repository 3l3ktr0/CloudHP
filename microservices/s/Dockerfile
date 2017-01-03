FROM python:3.4-alpine
ADD . /s
WORKDIR /s
RUN pip install flask pymysql
EXPOSE 5002
CMD ["python", "s.py"]
