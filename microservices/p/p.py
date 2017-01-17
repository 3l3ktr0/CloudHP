#!/usr/bin/env python3
# -*- coding: utf-8 -*-


"""Service P returns the BASE64 image stored in Swift"""

from flask import Flask
from flask import jsonify
from flask import abort
import logging
import requests
import swiftclient
import os

app = Flask(__name__)
app.debug = True

@app.route("/<id>")
def api_return_picture(id):
    logging.warning("*** Starting p ****")
    try:
        auth=os.environ['OS_AUTH_URL']
        user=os.environ['OS_USERNAME']
        pwd=os.environ['OS_PASSWORD']
        tenantname=os.environ['OS_TENANT_NAME']
        conn = swiftclient.Connection(authurl=auth, user=user, key=pwd, tenant_name=tenantname, auth_version='2')
        try:
            res =  conn.get_object('prices', "{}.txt".format(id))[1];
            res = res.decode('utf-8')
            return jsonify({'imgB64' : 'data:image/png;base64,{}'.format(res)})
        except Exception as e2:
            return jsonify({'imgB64': None})
    except Exception as e:
        abort(503) #DB unavailable

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5004)
