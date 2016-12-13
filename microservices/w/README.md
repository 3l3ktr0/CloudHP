# Service w

The purpose of this service is to define if the player win something.
A price is ramdomly selected, and an image is generated with the id of the player.
The ourput is a json with the price and the image data.

## Dependencies

- Python 3
- Imagemagick
- Flask (python3-flask)

## Configuration file

```
[w]
port=8090
tmpfile=/tmp
tempo=5
debug=False
```

* Port: Tcp port number used by the server.
* tmpfile: Location of the temporary price imaged.
* tempo: Latency introduced.
* debug: Add information to log file to debug the app.

## API

### Request
GET /

### Response

Return service name and version

```json
{

    "Service": "Microservice w",
    "Version": "0.1"

}
```

## Request
GET /play/id

### Response

Return price and base64 image data

```json
{

    "img": "/9j/4AAQSkZJRgABAQEASABIAAD/7RPqUGhvdG9zaG9wIDMuMAA4QklNBCUAAAAAABAAAAAAAAAAAAAAAAAAAAAAOEJJTQPtAAAAAAAQAEgAAAABAAIASAAAAAEAAjhCSU0EJgAAAAAADgAAAAAAAAAAAAA/gAAAOEJJTQQNAAAAAAAEAAAAHjh...
    "price": "usbkey.jpg"

}
```

## Request
POST /shutdown

### Response

Stop the application server

