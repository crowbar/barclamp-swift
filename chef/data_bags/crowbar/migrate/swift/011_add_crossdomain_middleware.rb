def upgrade ta, td, a, d
  a["middlewares"]["crossdomain"] = ta["middlewares"]["crossdomain"]
  return a, d
end

def downgrade ta, td, a, d
  a["middlewares"].delete("crossdomain")
  return a, d
end
