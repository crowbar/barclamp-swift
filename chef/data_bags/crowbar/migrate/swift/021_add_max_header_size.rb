def upgrade ta, td, a, d
  a['max_header_size'] = ta['max_header_size']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('max_header_size')
  return a, d
end
