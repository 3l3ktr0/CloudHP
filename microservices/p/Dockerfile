FROM python:3.4-alpine
ADD . /p
WORKDIR /p
RUN pip install flask requests
EXPOSE 5004
CMD ["python", "p.py"]
