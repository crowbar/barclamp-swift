def upgrade ta, td, a, d
  %w(gitrepo git_instance git_refspec use_gitbarclamp use_pip_cache use_gitrepo use_virtualenv pfs_deps).each do |attr|
    a.delete(attr)
  end
  %w(gitrepo git_refspec use_gitbarclamp use_gitrepo).each do |attr|
    a["middlewares"]["s3"].delete(attr)
  end
  return a, d
end

def downgrade ta, td, a, d
  %w(gitrepo git_instance git_refspec use_gitbarclamp use_pip_cache use_gitrepo use_virtualenv pfs_deps).each do |attr|
    a[attr] = ta[attr]
  end
  %w(gitrepo git_refspec use_gitbarclamp use_gitrepo).each do |attr|
    a["middlewares"]["s3"][attr] = ta["middlewares"]["s3"][attr]
  end
  return a, d
end
