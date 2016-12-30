from flask import Flask
from flask import render_template
from flask import request
import requests

app = Flask(__name__)

@app.route('/index.html')
def index():
    id = request.args.get('id', default=None, type=int)
    if id is None:
        return render_template('noidprovided.html')

    errors = {}
    services = {}

    #Service I
    bad_request = handle_service_i(id, services, errors)
    if bad_request:
        return render_template('noidprovided.html')

    handle_service_s(id, services, errors)

    return render_template('index.html', services=services, errors=errors)


def handle_service_i(id, services, errors):
    bad_request_check = False
    try:
        r = requests.get('http://127.0.0.1:5001/{}'.format(id))
        #check if id is out of range, if so, status_code is 400
        if (r.status_code == 400):
            bad_request_check = True
        else:
            services['i'] = r.json()
    except requests.exceptions.RequestException as e:
        errors['i'] = str(e)
    finally:
        return bad_request_check

def handle_service_s(id, services, errors):
    try:
        r = requests.get('http://127.0.0.1:5002/{}'.format(id))
        services['s'] = r.json()
    except requests.exceptions.RequestException as e:
        errors['s'] = str(e)

if __name__ == '__main__':
        app.run(port=5000)
