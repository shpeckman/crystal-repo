# src/crystal/repo/git.cr
module Crystal::Repo
  class GitError < Exception
    getter argv : Array(String)
    getter stderr : String

    def initialize(@argv : Array(String), @stderr : String)
      super("git #{argv.join(' ')} failed: #{stderr.strip}")
    end
  end

  class Git
    record StatusEntry, staged : Char, unstaged : Char, path : String do
      def untracked? : Bool
        staged == '?' && unstaged == '?'
      end
    end

    record Commit, sha : String, author : String, email : String, date : Time, subject : String
    record Branch, name : String, current : Bool, sha : String

    LOG_FORMAT = "%H%x1f%an%x1f%ae%x1f%aI%x1f%s%x1e"

    getter path : String

    def initialize(@path : String = ".")
    end

    def self.run(argv : Array(String), chdir : String? = nil) : String
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run("git", argv, chdir: chdir, output: stdout, error: stderr)
      raise GitError.new(argv, stderr.to_s) unless status.success?
      stdout.to_s
    end

    def run(argv : Array(String)) : String
      Git.run(argv, @path)
    end

    def self.init(path : String = ".", *, bare : Bool = false, initial_branch : String? = nil) : Git
      argv = ["init"]
      argv << "--bare" if bare
      argv << "--initial-branch=#{initial_branch}" if initial_branch
      argv << path
      run(argv)
      new(path)
    end

    def self.clone(url : String, dest : String? = nil, *, branch : String? = nil, depth : Int32? = nil, bare : Bool = false, chdir : String? = nil) : Git
      argv = ["clone"]
      argv << "--branch" << branch if branch
      argv << "--depth" << depth.to_s if depth
      argv << "--bare" if bare
      argv << url
      argv << dest if dest
      run(argv, chdir)
      target = dest || File.basename(url, ".git")
      new(chdir ? File.join(chdir, target) : target)
    end

    def config(key : String, value : String? = nil) : String?
      if value
        run(["config", key, value])
        nil
      else
        run(["config", "--get", key]).strip
      end
    end

    def add(*paths : String) : Nil
      argv = ["add"]
      argv << "-A" if paths.empty?
      paths.each { |p| argv << "--" << p }
      run(argv)
      nil
    end

    def commit(message : String, *, all : Bool = false, allow_empty : Bool = false, amend : Bool = false) : String
      argv = ["commit", "-m", message]
      argv << "-a" if all
      argv << "--allow-empty" if allow_empty
      argv << "--amend" if amend
      run(argv)
      rev_parse("HEAD")
    end

    def status : Array(StatusEntry)
      run(["status", "--porcelain"]).lines.compact_map do |line|
        next if line.size < 3
        StatusEntry.new(line[0], line[1], line[3..])
      end
    end

    def clean? : Bool
      status.empty?
    end

    def diff(*, cached : Bool = false, ref : String? = nil) : String
      argv = ["diff"]
      argv << "--cached" if cached
      argv << ref if ref
      run(argv)
    end

    def log(*, limit : Int32? = nil, ref : String = "HEAD") : Array(Commit)
      argv = ["log", ref, "--format=#{LOG_FORMAT}"]
      argv << "-n" << limit.to_s if limit
      run(argv).split('\u001e').map(&.strip).reject(&.empty?).map do |entry|
        fields = entry.split('\u001f')
        Commit.new(fields[0], fields[1], fields[2], Time.parse_rfc3339(fields[3]), fields[4])
      end
    end

    def branches : Array(Branch)
      run(["branch", "--format=%(HEAD) %(refname:short) %(objectname)"]).lines.compact_map do |line|
        next if line.empty?
        fields = line.split(' ', remove_empty: true)
        if fields[0] == "*"
          Branch.new(fields[1], true, fields[2])
        else
          Branch.new(fields[0], false, fields[1])
        end
      end
    end

    def current_branch : String
      run(["branch", "--show-current"]).strip
    end

    def create_branch(name : String, *, checkout : Bool = true, start_point : String? = nil) : Nil
      argv = checkout ? ["checkout", "-b", name] : ["branch", name]
      argv << start_point if start_point
      run(argv)
      nil
    end

    def checkout(ref : String) : Nil
      run(["checkout", ref])
      nil
    end

    def merge(branch : String, *, no_ff : Bool = false, message : String? = nil) : Nil
      argv = ["merge"]
      argv << "--no-ff" if no_ff
      argv << "-m" << message if message
      argv << branch
      run(argv)
      nil
    end

    def remotes : Hash(String, String)
      run(["remote", "-v"]).lines.each_with_object({} of String => String) do |line, hash|
        name, rest = line.split('\t', 2)
        hash[name] = rest.split(' ').first
      end
    end

    def remote_add(name : String, url : String) : Nil
      run(["remote", "add", name, url])
      nil
    end

    def remote_remove(name : String) : Nil
      run(["remote", "remove", name])
      nil
    end

    def fetch(remote : String? = nil, *, prune : Bool = false, all : Bool = false) : Nil
      argv = ["fetch"]
      argv << "--prune" if prune
      argv << "--all" if all
      argv << remote if remote
      run(argv)
      nil
    end

    def pull(remote : String = "origin", branch : String? = nil, *, rebase : Bool = false, ff_only : Bool = false) : Nil
      argv = ["pull"]
      argv << "--rebase" if rebase
      argv << "--ff-only" if ff_only
      argv << remote
      argv << branch if branch
      run(argv)
      nil
    end

    def push(remote : String = "origin", branch : String? = nil, *, set_upstream : Bool = false, force : Bool = false, tags : Bool = false) : Nil
      argv = ["push"]
      argv << "--set-upstream" if set_upstream
      argv << "--force-with-lease" if force
      argv << "--tags" if tags
      argv << remote
      argv << branch if branch
      run(argv)
      nil
    end

    def tags : Array(String)
      run(["tag", "--list"]).lines.map(&.strip).reject(&.empty?)
    end

    def create_tag(name : String, *, message : String? = nil, ref : String = "HEAD") : Nil
      argv = ["tag"]
      if message
        argv << "-a" << name << "-m" << message
      else
        argv << name
      end
      argv << ref
      run(argv)
      nil
    end

    def delete_tag(name : String, *, remote : String? = nil) : Nil
      run(["tag", "-d", name])
      run(["push", remote, ":refs/tags/#{name}"]) if remote
      nil
    end

    def rev_parse(ref : String = "HEAD") : String
      run(["rev-parse", ref]).strip
    end
  end
end
