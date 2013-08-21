#
# Copyright 2011, Dell
# Copyright 2013, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License atxf
#
#     http://www.apache.org/licenses/LICENSE-2.0cyt
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: andi abes
# Author: Judd Maltin
#
### The cluster hash is shared among all nodes in a swift cluster.
### can be generated using od -t x8 -N 8 -A n </dev/random
default[:swift][:cluster_hash]="fa8bea159b55bd7e"
### super user password - used for managing users.
default[:swift][:cluster_admin_pw]= "swauth"
### how many replicas should be made for each object
default[:swift][:replicas]= 1
## how many zones are in this cluster (should be >= # of replicas)
default[:swift][:zones]= 2
## minimum amount of time a partition should stay put, in hours
default[:swift][:min_part_hours]= 1
## number of bits to represent the partitions count
default[:swift][:partitions]= 18

### the uid/gid to be used for swift processes
case node[:platform]
when "suse"
  default[:swift][:user]= "openstack-swift"
  default[:swift][:group]= "openstack-swift"
else
  default[:swift][:user]= "swift"
  default[:swift][:group]= "swift"
end


default[:swift][:config] = {}
default[:swift][:config][:environment] = "default"

### where to find IP for admin use
default[:swift][:admin_ip_expr] = "node[:ipaddress]"
### where to find IP for storage network use
default[:swift][:storage_ip_expr] = "node[:ipaddress]"
### where to find IP for public network use (for clients to contact proxies)
default[:swift][:public_ip_expr] = "node[:ipaddress]"

# An expression to classify disks into zone's and assign them a weight.
# return
#   - nil: the disk is not included in the ring
#   - otherwise an array of [zone, weight]. Zone is an integer representing the zone # for the disk is expected, weight is the weight of the disk
# the default expression below just assigns disks in a round robin fashion.
#
# The expression is evaluated with the following context:
# - node - the Chef node hash
# - params - a hash with the following keys:
#   :ring=> one of "object", "account" or "container"
#   :disk=> disk partition information as created in disks.rb,contains: :name (e.g sdb) :size either :remaining (= all the disk) or an actual byte count.
default[:swift][:disk_zone_assign_expr] = '$DISK_CNT||=0; $DISK_CNT= $DISK_CNT+1 ;[ $DISK_CNT % node[:swift][:zones] , 99]'


# should proxy server account management be enabled
default[:swift][:account_management] = "true"

####
# new parameters for diablo


#
# the authentication method to use. possible values:
# keystone - use keystone (reuqired for swfit/dashboard integration
# swauth - Swifth authentication
# tempauth - use only for testing
default[:swift][:auth_method] = "keystone"
default[:swift][:keystone_instance] = "proposal"
default[:swift][:reseller_prefix] = "AUTH_"
default[:swift][:keystone_service_user] = "swift"
default[:swift][:keystone_service_password] = "swift"
default[:swift][:keystone_delay_auth_decision] = false

default[:swift][:install_slog_from_dev] = false



default[:keystone][:frontend] = 'apache'

