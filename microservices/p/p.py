#!/usr/bin/env python3
# -*- coding: utf-8 -*-


"""Service P play button service"""

from flask import Flask
from flask import jsonify
from flask import abort
import logging
import requests

app = Flask(__name__)
app.debug = True

@app.route("/<id>")
def api_identify(id):
    logging.warning("*** Starting p ****") 
    try:
        auth=os.environ['OS_AUTH_URL']
        user=os.environ['OS_USERNAME']
        pwd=os.environ['OS_PASSWORD']
        tenantname=os.environ['OS_TENANT_NAME']
        conn = swiftclient.Connection(authurl=auth, user=user, key=pwd, tenant_name=tenantname, auth_version='2')

        return conn.get_object('prices', id + ".txt")[1]

        
    except Exception as e:
        abort(503) #DB unavailable

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5004)
