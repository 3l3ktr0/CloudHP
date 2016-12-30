#!/usr/bin/env python3
# -*- coding: utf-8 -*-


"""Service I identifies the customer"""

from flask import Flask
from flask import jsonify
from flask import abort
#import config
import pymysql

app = Flask(__name__)
app.debug = True
#config.logger = app.logger

@app.route('/')
def hello_world():
    return 'Hello, World!'

@app.route("/<id>")
def api_identify(id):
    """ Get user info from DB with given ID """
    # config.logger.info("[Service-I] Start - id = %s", id)
    cust_info = get_user_info(id)
    return jsonify(cust_info) if cust_info is not None else abort(400)

def get_user_info(id):
    """ Return customer info as a dict """
    conn = pymysql.connect(host='localhost', user='root', passwd='root',
                           db='prestashop', cursorclass=pymysql.cursors.DictCursor)
    try:
        with conn.cursor() as cursor:
            query = "SELECT id_customer, firstname, lastname, email FROM ps_customer WHERE id_customer = %s"
            cursor.execute(query, (id,))
            res = cursor.fetchone()
            return res
    finally:
        conn.close()

if __name__ == '__main__':
        app.run(port=5001)
