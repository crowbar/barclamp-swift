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

f = package "xfsprogs" do
  action :nothing
end
f.run_action(:install)

def get_uuid(disk)
  uuid = nil
  IO.popen("blkid -c /dev/null -s UUID -o value #{disk}"){ |f|
    uuid=f.read.strip
  }
  return uuid if uuid && (uuid != '')
  nil
end

Chef::Log.info("locating disks using #{node[:swift][:disk_enum_expr]} test: #{node[:swift][:disk_test_expr]}")

to_use_disks = []
all_disks = eval(node[:swift][:disk_enum_expr])
all_disks.each { |k,v|
  b = binding()
  #skip if the disk is ahci and we have raid.
  next if v.is_ahci and node[:crowbar_wall].has_key?('raid')
  to_use_disks << k if eval(node[:swift][:disk_test_expr]) && ::File.exists?("/dev/#{k}")
}

Chef::Log.info("Swift will use these disks: #{to_use_disks.join(" ")}")

node[:swift] ||= Mash.new
node[:swift][:devs] ||= Mash.new
found_disks=[]
wait_for_format = false
to_use_disks.each do |k|

  target_suffix= k + "1" # by default, will use format first partition.
  target_dev = "/dev/#{k}"
  target_dev_part = "/dev/#{target_suffix}"

  disk = Hash.new
  disk[:device] = target_dev_part
  disk[:uuid] = get_uuid(target_dev_part)

  # Test to see if there is a partition table on the disk.
  # If not, create a shiny new GPT partition table for the disk.
  if ::Kernel.system("parted -s -m #{target_dev} print 1 |grep -q '^Error:'")
    Chef::Log.info("Swift - Creating partition table on #{target_dev}")
    ::Kernel.system("parted -s #{target_dev} -- unit s mklabel gpt mkpart primary ext2 2048s -1M")
    ::Kernel.system("partprobe #{target_dev}")
    sleep 3
    ::Kernel.system("dd if=/dev/zero of=#{target_dev_part} bs=1024 count=65")
    disk[:uuid] = nil
  end

  # Test to see if there is a file system, and create one if there is not.
  if disk[:uuid] && ! node[:swift][:devs][disk[:uuid]]
    # If there is already a file system and we don't already know about it,
    # then it belongs to someone else.  Print a log entry and skip it.
    Chef::Log.info("Swift - drive #{target_dev_part} alreay exists, and we don't own it.")
    Chef::Log.info("Please zero out the first and last meg of the drive if you want to use it for Swift")
    next
  elsif disk[:uuid].nil?
    # No filesystem.  Format that bad boy and claim it as our own.
    Chef::Log.info("Swift - formatting #{target_dev_part}")
    ::Kernel.exec "mkfs.xfs -i size=1024 -f #{target_dev_part}" unless ::Process.fork
    disk[:state] = "Fresh"
    wait_for_format = true
    found_disks << disk.dup
  else
    Chef::Log.info("Swift - #{target_dev_part} already known and used by Swift.")
  end
end

if wait_for_format
  Chef::Log.info("Swift -- Waiting on all disks to finish formatting")
  ::Process.waitall
end

# If we have freshly-claimed disks, add them and save them.
found_disks.each do |disk|
  # Disk was freshly created.  Grab its UUID and create a mount point.
  disk[:uuid] = get_uuid(disk[:device])
  disk[:state] = "Operational"
  disk[:name] = disk[:uuid].delete('-')
  Chef::Log.info("Adding new disk #{disk[:device]} with UUID #{disk[:uuid]} to the Swift config")
  node[:swift][:devs][disk[:uuid]] = disk.dup
end
node.save

# Take appropriate action for each disk.
node[:swift][:devs].each do |uuid,disk|
  # We always want a mountpoint created.
  directory "/srv/node/#{disk[:name]}" do
    group node[:swift][:group]
    owner node[:swift][:user]
    recursive true
    action :create
  end
  case disk[:state]
  when "Operational"
    # We want to use this disk.
    mount "/srv/node/#{disk[:name]}"  do
      device disk[:uuid]
      device_type :uuid
      options "noatime,nodiratime,nobarrier,logbufs=8"
      dump 0
      fstype "xfs"
      action [:mount, :enable]
    end
  else
    # We don't want this disk right now.  Maybe it is about to die.
    mount "/srv/node/#{disk[:name]}"  do
      device disk[:uuid]
      device_type :uuid
      options "noatime,nodiratime,nobarrier,logbufs=8"
      dump 0
      fstype "xfs"
      action [:umount, :disable]
    end
  end
end
