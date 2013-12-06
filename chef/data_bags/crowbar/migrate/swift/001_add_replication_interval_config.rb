def upgrade ta, td, a, d
  a['replication_interval'] = ta['replication_interval']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('replication_interval')
  return a, d
end
