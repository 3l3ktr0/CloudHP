#!/usr/bin/env python3
# -*- coding: utf-8 -*-


"""Service S checks whether the player has already played"""

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
def api_status(id):
    """ Checks if customer is present in DB """
    # config.logger.info("[Service-I] Start - id = %s", id)
    try:
        cust_info = get_user_info(id)
        return jsonify(cust_info)
    except Exception as e:
        abort(503)

def get_user_info(id):
    """ Return customer info as a dict """
    conn = pymysql.connect(host='db_s', user='root', passwd='root',
                           db='playstatus', cursorclass=pymysql.cursors.DictCursor)
    try:
        with conn.cursor() as cursor:
            query = "SELECT id_customer, playdate FROM customer_status WHERE id_customer = %s"
            res = cursor.execute(query, (id,))
            if res:
                return cursor.fetchone()
            else:
                return {'id_customer':id, 'playdate':None}
    finally:
        conn.close()

if __name__ == '__main__':
        app.run(host='0.0.0.0', port=5002)
