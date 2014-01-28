def upgrade ta, td, a, d
  a["allow_versions"] = ta["allow_versions"]
  return a, d
end

def downgrade ta, td, a, d
  a.delete("allow_versions")
  return a, d
end
