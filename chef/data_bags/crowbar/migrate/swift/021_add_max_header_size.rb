def upgrade ta, td, a, d
  a['max_header_size'] = 16384
  return a, d
end

def downgrade ta, td, a, d
  a.delete('max_header_size')
  return a, d
end
