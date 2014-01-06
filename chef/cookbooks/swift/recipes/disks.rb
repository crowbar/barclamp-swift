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

unclaimed_disks = BarclampLibrary::Barclamp::Inventory::Disk.unclaimed(node)
to_use_disks = []
unclaimed_disks.each do |k|
  to_use_disks << k
end
claimed_disks = BarclampLibrary::Barclamp::Inventory::Disk.claimed(node, "Swift")
claimed_disks.each do |k|
  to_use_disks << k
end

node[:swift] ||= Mash.new
node[:swift][:devs] ||= Mash.new
found_disks=[]
wait_for_format = false
to_use_disks.each do |d|

  k = d.device
  disk_name = k.gsub(/!/, "/")  # "cciss!c0d0"
  partition_suffix = "1" # by default, will use format first partition.
  partition_suffix = "p1" if k =~ /cciss/
  target_dev = "/dev/#{disk_name}"
  target_dev_part = "/dev/#{disk_name}#{partition_suffix}"

  disk = Hash.new
  disk[:device] = target_dev_part
  disk[:device_disk_name] = k
  disk[:device_disk_partition] = k + partition_suffix
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
    d.claim("Swift")
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
  # notify udev that there is a new UUID
  ::Kernel.system("echo change > /sys/block/#{disk[:device_disk_name]}/#{disk[:device_disk_partition]}/uevent")
  ::Kernel.system("/sbin/udevadm settle")

  disk[:state] = "Operational"
  disk[:name] = disk[:uuid].delete('-')
  Chef::Log.info("Adding new disk #{disk[:device]} with UUID #{disk[:uuid]} to the Swift config")
  node[:swift][:devs][disk[:uuid]] = disk.dup
end

# Now clean up list of claimed disks and remove those that do not
# exist anymore.
node[:swift][:devs].each do |uuid,disk|

  Chef::Log.info("Checking disk #{disk[:device]}")
  # Verify that UUID still matches
  current_uuid = get_uuid(disk[:device])
  if current_uuid != disk[:uuid]
    Chef::Log.warn("Disk #{disk[:device]} with UUID #{current_uuid} not matching expected UUID #{disk[:uuid]}")
    Chef::Log.info("Setting disk #{disk[:device]} to Stale")
    disk[:state] = "UUID_Stale"
    node[:swift][:devs][disk[:uuid]] = disk.dup
  end
end

# Save that data
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
      options "noatime,nodiratime,nobarrier,nofail,logbufs=8"
      dump 0
      pass 0
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
      pass 0
      fstype "xfs"
      action [:umount, :disable]
    end
  end
end
