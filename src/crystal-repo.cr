# src/crystal-repo.cr
module Crystal::Repo
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end

require "./crystal/repo/*"
