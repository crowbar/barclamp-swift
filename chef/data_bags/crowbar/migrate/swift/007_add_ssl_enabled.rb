def upgrade ta, td, a, d
  # before, it was always enabled, so keep that
  a["ssl"]["enabled"] = true
  return a, d
end

def downgrade ta, td, a, d
  a["ssl"].delete("enabled")
  return a, d
end
