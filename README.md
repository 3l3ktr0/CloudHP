# CloudHP

##Architecture

<img src="cloudhp_archi.png">

##Requirements :
-A Bastion VM, accessible from the outside with a floating IP.

-An Openstack private network (replace the NETWORK variable below with yours !)

-An Ubuntu-based image, tested with 1404, should work with 1604. Replace SSH_USER if necessary.

-A V2 OPENRC file. Get yours at "Access and Security -> API Access" on the Openstack dashboard.

-Basically, the requirements are the same steps we followed during the 2nd or 3rd lab session to set up the Bastion VM.

##How to deploy

-SSH into Bastion VM

-git clone the project

-Run the script ./init.sh.

You'll be asked for your Openstack password at the beginning,
the rest is 100% automated.

The script takes roughly 25min to complete.
