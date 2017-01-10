FROM python:3.4-alpine
ADD . /web
WORKDIR /web
RUN pip install flask requests
EXPOSE 5000
CMD ["python", "app/webpage.py"]
