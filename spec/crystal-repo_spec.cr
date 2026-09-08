# spec/crystal-repo_spec.cr
require "./spec_helper"

describe Repo do
  it "has a version" do
    Repo::VERSION.should_not be_empty
  end
end
