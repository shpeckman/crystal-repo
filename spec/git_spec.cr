# spec/git_spec.cr
require "./spec_helper"
require "file_utils"
require "random/secure"

private def with_tmpdir(& : String ->)
  dir = File.join(ENV["TMPDIR"]? || "/tmp", "crystal-repo-spec-#{Random::Secure.hex(8)}")
  Dir.mkdir(dir)
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

private def spec_repo(dir : String, name : String = "repo") : Crystal::Repo::Git
  git = Crystal::Repo::Git.init(File.join(dir, name), initial_branch: "main")
  git.config("user.name", "Spec")
  git.config("user.email", "spec@example.com")
  git.config("commit.gpgsign", "false")
  git
end

describe Crystal::Repo::Git do
  it "inits, commits and reads history" do
    with_tmpdir do |dir|
      git = spec_repo(dir)
      File.write(File.join(git.path, "hello.txt"), "hi\n")
      git.status.map(&.path).should contain("hello.txt")
      git.status.first.untracked?.should be_true
      git.add("hello.txt")
      sha = git.commit("initial commit")
      git.clean?.should be_true
      git.current_branch.should eq("main")
      git.rev_parse("HEAD").should eq(sha)
      log = git.log
      log.size.should eq(1)
      log[0].sha.should eq(sha)
      log[0].subject.should eq("initial commit")
      log[0].author.should eq("Spec")
      log[0].email.should eq("spec@example.com")
    end
  end

  it "manages branches, tags and remotes" do
    with_tmpdir do |dir|
      git = spec_repo(dir)
      File.write(File.join(git.path, "a.txt"), "a\n")
      git.add("a.txt")
      git.commit("init")
      git.create_branch("feature")
      git.current_branch.should eq("feature")
      git.branches.find(&.current).try(&.name).should eq("feature")
      git.branches.map(&.name).should contain("main")
      git.checkout("main")
      git.current_branch.should eq("main")
      git.create_tag("v1.0", message: "first")
      git.tags.should eq(["v1.0"])
      git.delete_tag("v1.0")
      git.tags.should be_empty
      git.remote_add("origin", "https://github.com/example/repo.git")
      git.remotes.should eq({"origin" => "https://github.com/example/repo.git"})
      git.remote_remove("origin")
      git.remotes.should be_empty
    end
  end

  it "clones a local repository" do
    with_tmpdir do |dir|
      git = spec_repo(dir, "src")
      File.write(File.join(git.path, "a.txt"), "a\n")
      git.add("a.txt")
      git.commit("init")
      copy = Crystal::Repo::Git.clone(git.path, File.join(dir, "copy"))
      copy.rev_parse("HEAD").should eq(git.rev_parse("HEAD"))
      copy.current_branch.should eq("main")
    end
  end

  it "reports diffs" do
    with_tmpdir do |dir|
      git = spec_repo(dir)
      File.write(File.join(git.path, "a.txt"), "a\n")
      git.add("a.txt")
      git.commit("init")
      File.write(File.join(git.path, "a.txt"), "a\nb\n")
      git.diff.should contain("+b")
      git.diff(cached: true).should be_empty
    end
  end

  it "raises GitError on failure" do
    with_tmpdir do |dir|
      git = Crystal::Repo::Git.init(dir)
      error = expect_raises(Crystal::Repo::GitError) { git.rev_parse("HEAD") }
      error.argv.should eq(["rev-parse", "HEAD"])
      error.message.to_s.should contain("git rev-parse HEAD failed")
    end
  end
end
