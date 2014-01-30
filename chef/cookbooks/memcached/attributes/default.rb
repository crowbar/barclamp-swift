default[:memcached][:memory] = 64
default[:memcached][:port] = 11211
default[:memcached][:listen] = "0.0.0.0"
case node[:platform]
when "suse"
  default[:memcached][:user] = "memcached"
else
  default[:memcached][:user] = "nobody"
end
