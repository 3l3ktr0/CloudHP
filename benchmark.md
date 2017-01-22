# Test results #
Tools : cURL and Siege (found it thanks to the mailing-list :) )

##  4 concurrent requests on the B service ##
### Using Siege ###
```
Transactions:		           4 hits
Availability:		      100.00 %
Elapsed time:		       11.38 secs
Data transferred:	        0.00 MB
Response time:		        8.64 secs
Transaction rate:	        0.35 trans/sec
Throughput:		        0.00 MB/sec
Concurrency:		        3.04
Successful transactions:           4
Failed transactions:	           0
Longest transaction:	       11.37
Shortest transaction:	        6.0
```
**Commentary:** we are more of less close to the bonus criteria of "4 requests in less than 10 seconds".

### Using cURL ###
```
-------------------------------------------------------
real	0m6.323s
user	0m0.008s
sys	0m0.004s
-------------------------------------------------------
real	0m6.276s
user	0m0.012s
sys	0m0.000s
-------------------------------------------------------
real	0m6.269s
user	0m0.008s
sys	0m0.004s
-------------------------------------------------------
real	0m11.255s
user	0m0.008s
sys	0m0.008s
-------------------------------------------------------
```
**Commentary:** The details show that three of the requests take about 6 seconds, 
but also that apparently the last request was somewhat badly load-balanced by Swarm
and was surely processed by the same container used for one of the first 3 requests.

The tests were repeated a few more times and the results were still on the same order of magnitude.
At the very least, our application has a "predictible" behavior.

## Access to the web page ##
### Page of a player that hasn't played yet. 100 concurrent users ###
(to be more accurate, 200 requests are made in total, because of the CSS style)
```
Transactions:		         200 hits
Availability:		      100.00 %
Elapsed time:		        9.08 secs
Data transferred:	       11.73 MB
Response time:		        2.72 secs
Transaction rate:	       22.03 trans/sec
Throughput:		        1.29 MB/sec
Concurrency:		       60.01
Successful transactions:         200
Failed transactions:	           0
Longest transaction:	        7.15
Shortest transaction:	        0.56
```
**Commentary:** The average response time is 2.72 seconds, the longest being 7.15s. The results look perfectly fine
and show that some load-balancing is operating for the server to withstand such a number of requests at the same time.

NGINX and uwsgi are also working. Indeed, the Flask development server wouldn't be able to handle so many requests at once
and would have given much worse results.

### Page of a player that has already played. 100 concurrent users ###
(also 200 requests in practice)
```
Transactions:		         200 hits
Availability:		      100.00 %
Elapsed time:		       33.38 secs
Data transferred:	       34.81 MB
Response time:		       13.52 secs
Transaction rate:	        5.99 trans/sec
Throughput:		        1.04 MB/sec
Concurrency:		       81.04
Successful transactions:         200
Failed transactions:	           0
Longest transaction:	       31.30
Shortest transaction:	        0.57
```
**Commentary**: We can see that the server has difficulties to respond quickly when it also has to download an image
(in base64 format). Maybe there is also some latency because of Swift: is this Openstack component supposed to
handle many concurrent requests ?

On the bright side, we notice that the other measures are similar to that of the first case, especially the throughput
and the transaction rate. Also, every transaction was successful in the end, maybe that's the most important thing after all.
