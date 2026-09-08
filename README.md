# crystal-repo

Git CLI wrapper and GitHub REST API client for Crystal.

`crystal-repo` provides two building blocks under the `Repo` namespace:

- **`Repo::Git`** — an ergonomic wrapper around the `git` command-line tool: init, clone, status, diff, log, branches, tags, remotes, fetch/pull/push, and more. Every invocation is executed through `Process.run` with captured stdout/stderr, and failures raise `Repo::GitError` with the full argv and stderr.
- **`Repo::GitHub`** — a minimal client for the GitHub REST API (version `2022-11-28`): repos, branches, tags, commits, contents, issues, pull requests, releases, search, and rate limits. Responses are returned as `JSON::Any`; non-2xx responses raise `Repo::GitHubError` with the parsed API error message.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  crystal-repo:
    github: shpeckman/crystal-repo
```

Then run:

```sh
shards install
```

Requires Crystal `>= 1.21.0` and the `git` executable on `PATH` (for `Repo::Git`).

## Usage

### Working with local repositories

```crystal
require "crystal-repo"

git = Repo::Git.init("/tmp/my-project", initial_branch: "main")
git.config("user.name", "You")
git.config("user.email", "you@example.com")

File.write("/tmp/my-project/hello.txt", "hello\n")
git.add("hello.txt")
sha = git.commit("initial commit")

git.status       # => Array(Repo::Git::StatusEntry)
git.clean?       # => true
git.log(limit: 5).each do |commit|
  puts "#{commit.sha[0, 7]} #{commit.subject}"
end

git.create_branch("feature")
git.create_tag("v0.1.0", message: "first release")
git.tags         # => ["v0.1.0"]
```

Cloning works too:

```crystal
repo = Repo::Git.clone("https://github.com/owner/repo.git", dest: "/tmp/repo", depth: 1)
repo.current_branch # => "main"
```

### Talking to the GitHub API

```crystal
require "crystal-repo"

github = Repo::GitHub.from_env # reads GITHUB_TOKEN
# or: Repo::GitHub.new("ghp_...")

repo = github.repo("crystal-lang", "crystal")
puts repo["description"].as_s

github.issues("crystal-lang", "crystal", state: "open", per_page: 10).each do |issue|
  puts "##{issue["number"]}: #{issue["title"]}"
end

# Pagination helper walks pages until a short page is returned:
all_branches = github.paginate("/repos/crystal-lang/crystal/branches")

# Write operations:
github.create_issue("owner", "repo", "Bug report", body: "It broke.")
github.create_release("owner", "repo", "v1.0.0", title: "v1.0.0")
```

All endpoints return `JSON::Any`, so you decide how much structure to impose.

## API Reference

### `Repo`

- `Repo::VERSION : String` — the shard version, read from `shard.yml` at compile time.

### `Repo::Git`

Wraps the `git` CLI. All methods run git in the repository at `#path` and raise `Repo::GitError` on a non-zero exit.

**Exceptions and records**

- `Repo::GitError < Exception` — `#argv : Array(String)`, `#stderr : String`.
- `Repo::Git::StatusEntry` — `staged : Char`, `unstaged : Char`, `path : String`; `#untracked? : Bool`.
- `Repo::Git::Commit` — `sha : String`, `author : String`, `email : String`, `date : Time`, `subject : String`.
- `Repo::Git::Branch` — `name : String`, `current : Bool`, `sha : String`.

**Constructors and low-level execution**

- `.new(path : String = ".")` — wrap the repository at `path`.
- `.init(path : String = ".", *, bare : Bool = false, initial_branch : String? = nil) : Git` — `git init`, returns a `Git` for the new repo.
- `.clone(url : String, dest : String? = nil, *, branch : String? = nil, depth : Int32? = nil, bare : Bool = false, chdir : String? = nil) : Git` — `git clone`, returns a `Git` for the clone.
- `.run(argv : Array(String), chdir : String? = nil) : String` — run git once, return stdout.
- `#run(argv : Array(String)) : String` — same, in this repo.

**Staging and committing**

- `#config(key : String, value : String? = nil) : String?` — get (no value) or set a config key.
- `#add(*paths : String) : Nil` — stage paths; with no paths, stages everything (`-A`).
- `#commit(message : String, *, all : Bool = false, allow_empty : Bool = false, amend : Bool = false) : String` — commit, returns the new HEAD sha.
- `#status : Array(StatusEntry)` — porcelain status entries.
- `#clean? : Bool` — true when status is empty.
- `#diff(*, cached : Bool = false, ref : String? = nil) : String` — raw diff output.

**History and branches**

- `#log(*, limit : Int32? = nil, ref : String = "HEAD") : Array(Commit)` — parsed commit history.
- `#branches : Array(Branch)` — local branches with current marker and sha.
- `#current_branch : String`
- `#create_branch(name : String, *, checkout : Bool = true, start_point : String? = nil) : Nil`
- `#checkout(ref : String) : Nil`
- `#merge(branch : String, *, no_ff : Bool = false, message : String? = nil) : Nil`
- `#rev_parse(ref : String = "HEAD") : String` — resolve a ref to a sha.

**Remotes**

- `#remotes : Hash(String, String)` — remote name to URL.
- `#remote_add(name : String, url : String) : Nil`
- `#remote_remove(name : String) : Nil`
- `#fetch(remote : String? = nil, *, prune : Bool = false, all : Bool = false) : Nil`
- `#pull(remote : String = "origin", branch : String? = nil, *, rebase : Bool = false, ff_only : Bool = false) : Nil`
- `#push(remote : String = "origin", branch : String? = nil, *, set_upstream : Bool = false, force : Bool = false, tags : Bool = false) : Nil` — `force` uses `--force-with-lease`.

**Tags**

- `#tags : Array(String)`
- `#create_tag(name : String, *, message : String? = nil, ref : String = "HEAD") : Nil` — annotated when `message` is given.
- `#delete_tag(name : String, *, remote : String? = nil) : Nil` — also deletes on the remote when given.

### `Repo::GitHub`

Minimal GitHub REST API client (API version `2022-11-28`). Read endpoints return `JSON::Any`; list endpoints return `Array(JSON::Any)`; failures raise `Repo::GitHubError`.

**Exceptions and construction**

- `Repo::GitHubError < Exception` — `#status : HTTP::Status`, `#body : String`; the message is extracted from the API error payload when possible.
- `.new(token : String? = nil, api_url : String = DEFAULT_API_URL)`
- `.from_env(var : String = "GITHUB_TOKEN") : GitHub`
- Constants: `DEFAULT_API_URL`, `API_VERSION`, `USER_AGENT`.

**HTTP primitives**

- `#build_request(method : String, path : String, query : URI::Params? = nil, body : String? = nil) : HTTP::Request` — builds a request with Accept, User-Agent, API-version, and (when a token is set) Authorization headers.
- `#get(path, query = nil) : JSON::Any` / `#post(path, body = nil)` / `#patch(path, body = nil)` / `#put(path, body = nil)` / `#delete(path) : JSON::Any`
- `#paginate(path : String, query : URI::Params = URI::Params.new, *, per_page : Int32 = 100, max_pages : Int32? = nil) : Array(JSON::Any)` — follows pages until a short page or `max_pages`.

**Users and rate limit**

- `#rate_limit : JSON::Any`
- `#user : JSON::Any` — the authenticated user; `#user(login : String)` — any user.

**Repositories**

- `#repo(owner, repo) : JSON::Any`
- `#repos(*, per_page = 30, page = 1, sort = nil, type = nil) : Array(JSON::Any)` — authenticated user's repos.
- `#org_repos(org, *, per_page = 30, page = 1, type = nil) : Array(JSON::Any)`
- `#create_repo(name, *, description = nil, private_repo = false, auto_init = false) : JSON::Any`
- `#delete_repo(owner, repo) : Nil`
- `#branches(owner, repo, *, per_page = 30, page = 1) : Array(JSON::Any)`
- `#tags(owner, repo, *, per_page = 30, page = 1) : Array(JSON::Any)`
- `#commits(owner, repo, *, sha = nil, path = nil, per_page = 30, page = 1) : Array(JSON::Any)`
- `#contents(owner, repo, path = "", *, ref = nil) : JSON::Any`

**Issues**

- `#issues(owner, repo, *, state = "open", labels = nil, per_page = 30, page = 1) : Array(JSON::Any)`
- `#issue(owner, repo, number) : JSON::Any`
- `#create_issue(owner, repo, title, *, body = nil, labels = nil, assignees = nil) : JSON::Any`
- `#update_issue(owner, repo, number, *, title = nil, body = nil, state = nil, labels = nil, assignees = nil) : JSON::Any`
- `#close_issue(owner, repo, number) : JSON::Any`
- `#issue_comments(owner, repo, number, *, per_page = 30, page = 1) : Array(JSON::Any)`
- `#comment_issue(owner, repo, number, body) : JSON::Any`

**Pull requests**

- `#pull_requests(owner, repo, *, state = "open", head = nil, base = nil, per_page = 30, page = 1) : Array(JSON::Any)`
- `#pull_request(owner, repo, number) : JSON::Any`
- `#create_pull_request(owner, repo, title, head, base, *, body = nil, draft = false) : JSON::Any`
- `#update_pull_request(owner, repo, number, *, title = nil, body = nil, state = nil, base = nil) : JSON::Any`
- `#close_pull_request(owner, repo, number) : JSON::Any`
- `#merge_pull_request(owner, repo, number, *, merge_method = "merge", commit_title = nil) : JSON::Any`

**Releases**

- `#releases(owner, repo, *, per_page = 30, page = 1) : Array(JSON::Any)`
- `#latest_release(owner, repo) : JSON::Any`
- `#release_by_tag(owner, repo, tag) : JSON::Any`
- `#create_release(owner, repo, tag, *, title = nil, body = nil, target = nil, draft = false, prerelease = false) : JSON::Any`

**Search**

- `#search_repositories(q, *, sort = nil, order = nil, per_page = 30, page = 1) : JSON::Any`
- `#search_issues(q, *, sort = nil, order = nil, per_page = 30, page = 1) : JSON::Any`
- `#search_users(q, *, sort = nil, order = nil, per_page = 30, page = 1) : JSON::Any`
- `#search_code(q, *, sort = nil, order = nil, per_page = 30, page = 1) : JSON::Any`

Each returns the search envelope (`total_count`, `items`, ...).

## Running the specs

```sh
crystal spec
```

The suite runs entirely offline: `Repo::Git` specs operate on temporary local repositories and `Repo::GitHub` specs only inspect request construction and error handling.

An additional live-API spec is included but skipped by default. To run it (requires network access, and optionally a `GITHUB_TOKEN` for a higher rate limit):

```sh
CRYSTAL_REPO_LIVE=1 crystal spec
```

## License

MIT
