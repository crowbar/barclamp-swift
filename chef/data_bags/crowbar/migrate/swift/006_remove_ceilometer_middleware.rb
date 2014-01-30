def upgrade ta, td, a, d
  a["middlewares"].delete("ceilometer")
  return a, d
end

def downgrade ta, td, a, d
  a["middlewares"]["ceilometer"] = ta["middlewares"]["ceilometer"]
  return a, d
end
