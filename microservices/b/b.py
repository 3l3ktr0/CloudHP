#!/usr/bin/env python3
# -*- coding: utf-8 -*-


"""Service B play button service"""

from flask import Flask
from flask import jsonify
from flask import abort
#import config
import requests

app = Flask(__name__)
app.debug = True
#config.logger = app.logger

@app.route('/')
def hello_world():
    return 'Hello, World!'

@app.route("/<id>")
def api_identify(id):
    try:
        bad_request_check = False
        try:
            r = requests.get('http://w:8090/play/{}'.format(id))
            #check if id is out of range, if so, status_code is 400
            if (r.status_code == 400):
                bad_request_check = True
            elif (r.status_code == 200):
                services['b'] = r.json()
            else:
                errors['b'] = "placeholder"
        except requests.exceptions.RequestException as e:
            errors['b'] = str(e)
        finally:
            return r
    except Exception as e:
        abort(503) #DB unavailable

if __name__ == '__main__':
        app.run(host='0.0.0.0', port=5001)
