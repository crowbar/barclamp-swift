def upgrade ta, td, a, d
  a['service_user'] = a['keystone_service_user']
  a['service_password'] = a['keystone_service_password']
  a.delete('keystone_service_user')
  a.delete('keystone_service_password')
  return a, d
end

def downgrade ta, td, a, d
  a['keystone_service_user'] = a['service_user']
  a['keystone_service_password'] = a['service_password']
  a.delete('service_user')
  a.delete('service_password')
  return a, d
end
