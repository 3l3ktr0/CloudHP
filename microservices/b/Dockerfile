FROM b_p_common
RUN pip3 install pymysql
ADD . /b
WORKDIR /b
EXPOSE 5003
CMD ["python", "b.py"]
