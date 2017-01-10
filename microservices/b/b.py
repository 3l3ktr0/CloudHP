#!/usr/bin/env python3
# -*- coding: utf-8 -*-


"""Service B play button service"""

from flask import Flask
from flask import jsonify
from flask import abort
import logging
import requests

app = Flask(__name__)
app.debug = True

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
            
            return jsonify({"message": "Bonsoir"})
        else:
            errors['b'] = "placeholder"
    except Exception as e:
        abort(503) #DB unavailable

if __name__ == '__main__':
        app.run(host='0.0.0.0', port=5003)
