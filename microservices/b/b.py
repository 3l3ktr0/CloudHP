#!/usr/bin/env python3
# -*- coding: utf-8 -*-


"""Service B play button service"""

from flask import Flask
from flask import jsonify
from flask import abort
import logging
import requests
import swiftclient
import pymysql
import os

app = Flask(__name__)
app.debug = True

@app.route("/")
def api_check_alive():
    return jsonify({'b':'alive'})

@app.route("/<id>")
def api_identify(id):
    logging.warning("*** Starting b ****")
    bad_request_check = False
    try:
        # Récupère l'image et le prix remporté par l'utilisateur
        r = requests.get('http://w:8090/play/{}'.format(id))

        if (r.status_code == 400):
            bad_request_check = True
        elif (r.status_code == 200):
            res_w = r.json()
            logging.warning(res_w)

            # Enregistrement de l'image dans SWIFT
            auth=os.environ['OS_AUTH_URL']
            user=os.environ['OS_USERNAME']
            pwd=os.environ['OS_PASSWORD']
            tenantname=os.environ['OS_TENANT_NAME']

            conn = swiftclient.Connection(authurl=auth, user=user, key=pwd, tenant_name=tenantname, auth_version='2')
            conn.put_object('prices', '{}.txt'.format(id), contents=res_w['img'])

            #on insère dans la BD le fait que l'utilisateur a joué
            conn2 = pymysql.connect(host='db_s', user='root', passwd='root',
                                    db='playstatus', cursorclass=pymysql.cursors.DictCursor)
            try:
                with conn2.cursor() as cur:
                    query = "INSERT INTO customer_status(id_customer, playdate) VALUES (%s, NOW())"
                    cur.execute(query, (id,))
                conn2.commit()
            finally:
                conn2.close()

            return jsonify({"message": "Bonsoir"})
        else:
            return jsonify({"message": "W failed"}) #to change ?
    except Exception as e:
        abort(503)

if __name__ == '__main__':
        app.run(host='0.0.0.0', port=5003)
