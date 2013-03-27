> NOTE: move to Swift Barclamp dir


See all, [[Barclamp List]]

//This is a Creole document//

## Overview

This barclamp deploys Openstack Swift.
Here are a few quick notes about what's required:
A few quick tidbits and a warning:

1. Swift storage nodes will use all available disks (other than the first one /dev/sda) on a node.  To install swift you need to have your storage nodes w/ at least 2 disks
1. Swift uses the ‘storage’ and ‘public’ networks. The proxy nodes communicate with the storage nodes over the  ‘storage’ network. By default it uses vlan 200. If this network is not functional, setup will fail
1. You need to have at least as many storage nodes as zones (the defaults are currently setup for easy testing w/ just 2 storage nodes)
1. The default disk <-> zone mapping is pretty rudimentary, and uses a simple round robin scheme… 
1. If you choose to use keystone authentication, you must first install keystone and its dependencies
1. Swift-proxy and swift-proxy-acct are almost the same, with the distinction that swift-proxy-acct has swauth account management enabled. You probably want the –acct if you’re deploying w/ swauth

Once you’ve ensured the above is ok, just create a proposal for swift, choose your nodes and have at it ;)
All that said, I’m chasing an issue where you need to run a few chef-client runs manually on the storage nodes, then the proxy nodes to get the deployment to a full working state. Should be fixed shortly.




## Roles

   * swift-proxy, swift-proxy-acct - The swift proxy. The -acct variant enables swauth account management api
   * swift-storage - a role which deploys the account, container and object servers on the system, using all the available disks
   * swift-ring-compute - only a single node should have this role. It's responsible for find all the disks in all swift-storage nodes and creating/updating the 3 rings for the cluster.


## Scripts



## Parameters

The barclamp has the following parameters:

| **Name** | **Default** | **Description** |
|----------|-------------|-----------------|
| start_up_delay | 30 | A number in seconds that the chef recipe should wait to let the networks settle. |


## Testing it out

This assumes you set up using swauth and left the admin password default (to `swauth`)

    # prepare swauth (if you disabled SSL, the -A flag is not needed)
    swauth-prep -K swauth -A https://127.0.0.1:8080/auth/
    # create account a_test
    swauth-add-account -K swauth -U '.super_admin' -A https://127.0.0.1:8080/auth/ a_test 
    # in this account, create user test (password test)
    swauth-add-user -K swauth -U '.super_admin' -A https://127.0.0.1:8080/auth/ -a a_test test test
    # get authentication tokens for this user
    curl -k -D o_hdr.txt -H "X-Auth-User: a_test:test" -H "X-Auth-Key: test" https://127.0.0.1:8080/auth/v1.0/

The output of the last command will be something like: `{"storage": {"default": "local", "local": " https://192.168.124.131:8080/v1/AUTH_c0c05fb6-4d19-4b06-89d0-e58d7c325ed3" }`

The file o_hdr.txt will be created to hold the returned HTTP headers, it should look like:

    HTTP/1.1 200 OK
    X-Storage-Url: https://192.168.124.131:8080/v1/AUTH_c0c05fb6-4d19-4b06-89d0-e58d7c325ed3 
    X-Storage-Token: AUTH_tk287a53a7464d4efd9026b0c9ac97d4df
    X-Auth-Token: AUTH_tk287a53a7464d4efd9026b0c9ac97d4df
    Content-Length: 119
    Date: Wed, 25 May 2011 21:15:07 GMT

Using this information, you can continue:

    # for your convenience, store the relevant information in variables (it'll be used in many commands):
    # X-HTTP-Storage-URL: account specific URL. All subsequent actions will be directed at this base url
    url=$(grep ^X-Storage-Url o_hdr.txt | cut -d ' ' -f2 | tr -d '\r')
    # X-Auth-Token: authentication token for this user. It must be included in all future requests.
    token=$(grep ^X-Auth-Token o_hdr.txt | cut -d ' ' -f2 | tr -d '\r')
    # create container test_container (X-Auth-User header is in the format - account:user)
    curl -k -D - -H "X-Auth-Token: $token" -H "X-Auth-User: a_test:test" $url/test_container -X PUT
    # put a file into swift
    curl -k -D - -H "X-Auth-Token: $token" -H "X-Auth-User: a_test:test" $url/test_container/file -X PUT -T /path/to/local.file
    #read the file from swift
    curl -k -D - -H "X-Auth-Token: $token" -H "X-Auth-User: a_test:test" $url/test_container/file


