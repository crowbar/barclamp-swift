#
# Copyright 2011, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: andi abes
#

package "curl" do
  action :upgrade
end

case node[:platform]
when "suse"
  package "openstack-swift" do
    action :upgrade
  end
else
  package "swift" do
    action :upgrade
  end
end

directory "/etc/swift" do
  owner node[:swift][:user]
  group node[:swift][:group]
  mode "0755"
end

template "/etc/swift/swift.conf" do
  owner node[:swift][:user]
  group node[:swift][:group]
  source "swift.conf.erb"  
 variables( {
       :swift_cluster_hash => node[:swift][:cluster_hash]
 })
end

directory "/var/lock/swift" do
  owner node[:swift][:user]
  group node[:swift][:group]
  mode "0755"
end
