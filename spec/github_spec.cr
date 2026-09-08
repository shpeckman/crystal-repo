# spec/github_spec.cr
require "./spec_helper"

describe Repo::GitHub do
  it "builds requests with auth and api headers" do
    github  = Repo::GitHub.new("token123")
    request = github.build_request("GET", "/repos/crystal-lang/crystal")
    request.method.should eq("GET")
    request.resource.should eq("/repos/crystal-lang/crystal")
    request.headers["Authorization"].should eq("Bearer token123")
    request.headers["Accept"].should eq("application/vnd.github+json")
    request.headers["X-GitHub-Api-Version"].should eq("2022-11-28")
    request.headers["User-Agent"].should contain("crystal-repo")
  end

  it "appends query params and json bodies" do
    github = Repo::GitHub.new
    query  = URI::Params.new
    query["per_page"] = "10"
    request = github.build_request("POST", "user/repos", query, %({"name":"x"}))
    request.resource.should eq("/user/repos?per_page=10")
    request.path.should eq("/user/repos")
    request.headers["Authorization"]?.should be_nil
    request.headers["Content-Type"].should eq("application/json")
    request.body.try(&.gets_to_end).should eq(%({"name":"x"}))
  end

  it "reads the token from the environment" do
    ENV["CRYSTAL_REPO_SPEC_TOKEN"] = "abc"
    Repo::GitHub.from_env("CRYSTAL_REPO_SPEC_TOKEN").token.should eq("abc")
    ENV.delete("CRYSTAL_REPO_SPEC_TOKEN")
    Repo::GitHub.from_env("CRYSTAL_REPO_SPEC_TOKEN").token.should be_nil
  end

  it "extracts the message from error payloads" do
    error = Repo::GitHubError.new(HTTP::Status::NOT_FOUND, %({"message":"Not Found"}))
    error.status.should eq(HTTP::Status::NOT_FOUND)
    error.message.to_s.should contain("Not Found")
    plain = Repo::GitHubError.new(HTTP::Status::INTERNAL_SERVER_ERROR, "boom")
    plain.message.to_s.should contain("boom")
  end

  if ENV["CRYSTAL_REPO_LIVE"]?
    it "queries the live api" do
      github = Repo::GitHub.from_env
      repo   = github.repo("crystal-lang", "crystal")
      repo["name"].as_s.should eq("crystal")
      repo["full_name"].as_s.should eq("crystal-lang/crystal")
      github.branches("crystal-lang", "crystal", per_page: 5).should_not be_empty
      github.latest_release("crystal-lang", "crystal")["tag_name"].as_s.should_not be_empty
      results = github.search_repositories("crystal language:crystal", per_page: 5)
      results["total_count"].as_i.should be > 0
      github.rate_limit["resources"].as_h.should_not be_empty
    end
  end
end
