# spec/crystal-repo_spec.cr
require "./spec_helper"

describe Crystal::Repo do
  it "has a version" do
    Crystal::Repo::VERSION.should_not be_empty
  end
end
