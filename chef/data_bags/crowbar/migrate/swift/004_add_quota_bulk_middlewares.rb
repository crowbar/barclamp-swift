def upgrade ta, td, a, d
  a["middlewares"]["bulk"] = ta["middlewares"]["bulk"]
  return a, d
end

def downgrade ta, td, a, d
  a["middlewares"].delete("bulk")
  return a, d
end
