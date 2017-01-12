#!/usr/bin/env python3
# -*- coding: utf-8 -*-


"""Service I identifies the customer"""

from flask import Flask
from flask import jsonify
from flask import abort
import pymysql

app = Flask(__name__)
app.debug = True

@app.route('/')
def hello_world():
    return 'Hello, World!'

@app.route("/<id>")
def api_identify(id):
    """ Get user info from DB with given ID """
    # config.logger.info("[Service-I] Start - id = %s", id)
    try:
        cust_info = get_user_info(id)
        return jsonify(cust_info) if cust_info is not None else abort(400)
    except Exception as e:
        abort(503) #DB unavailable

def get_user_info(id):
    """ Return customer info as a dict """
    conn = pymysql.connect(host='db_i', user='root', passwd='root',
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
        app.run(host='0.0.0.0', port=5001)
