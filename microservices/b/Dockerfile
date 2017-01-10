FROM python:3.4-alpine
ADD . /b
WORKDIR /b
RUN pip install flask requests logging
EXPOSE 5003
CMD ["python", "b.py"]
