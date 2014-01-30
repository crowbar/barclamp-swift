def upgrade ta, td, a, d
  a["middlewares"].delete("ceilometer")
  return a, d
end

def downgrade ta, td, a, d
  a["middlewares"]["ceilometer"] = {}
  a["middlewares"]["ceilometer"]["enabled"] = ta["middlewares"]["ceilometer"]["enabled"]
  return a, d
end
