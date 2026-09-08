# src/crystal-repo.cr
module Repo
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end

require "./repo/*"
