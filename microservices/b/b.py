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
def api_play_b(id):
    logging.warning("*** Starting b ****")
    bad_request_check = False
    try:
        # Récupère l'image et le prix remporté par l'utilisateur
        r = requests.get('http://w:8090/play/{}'.format(id))

        if (r.status_code == 400):
            bad_request_check = True
        elif (r.status_code == 200):
            res_w = r.json()

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

            #on envoie un mail à corentin.cournac@live.fr
            requests.post(
		        "https://api.mailgun.net/v3/sandboxf9c61421eb35444f9ef513f6a6701216.mailgun.org/messages",
		        auth=("api", "key-eaa84720c1d35afda7164df735889061"),
		        data={"from": "Openstack Notifications <noreply@openswag.fr>",
		              "to": "Corentin Cournac <corentin.cournac@live.fr>",
		              "subject": "User "+str(id)+" played the game",
		              "text": "User "+str(id)+" just won the game. Go watch on the website and conctact him to agree to stuff"})


            return jsonify({"message": "You won !"})
        else:
            return jsonify({"message": "W failed"}) #to change ?
    except Exception as e:
        abort(503)

if __name__ == '__main__':
        app.run()
