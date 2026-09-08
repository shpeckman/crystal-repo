# src/crystal/repo/github.cr
require "http/client"
require "json"
require "uri"

module Crystal::Repo
  class GitHubError < Exception
    getter status : HTTP::Status
    getter body : String

    def initialize(@status : HTTP::Status, @body : String)
      detail = begin
        JSON.parse(body)["message"].as_s
      rescue
        body
      end
      super("GitHub API #{status.code}: #{detail}")
    end
  end

  class GitHub
    DEFAULT_API_URL = "https://api.github.com"
    API_VERSION     = "2022-11-28"
    USER_AGENT      = "crystal-repo/#{VERSION}"

    getter api_url : URI
    getter token : String?

    def initialize(@token : String? = nil, api_url : String = DEFAULT_API_URL)
      @api_url = URI.parse(api_url)
    end

    def self.from_env(var : String = "GITHUB_TOKEN") : GitHub
      new(ENV[var]?)
    end

    def build_request(method : String, path : String, query : URI::Params? = nil, body : String? = nil) : HTTP::Request
      resource = path.starts_with?("/") ? path : "/#{path}"
      resource = "#{resource}?#{query}" if query && !query.empty?
      headers = HTTP::Headers{
        "Accept"               => "application/vnd.github+json",
        "User-Agent"           => USER_AGENT,
        "X-GitHub-Api-Version" => API_VERSION,
      }
      if token = @token
        headers["Authorization"] = "Bearer #{token}"
      end
      if body
        headers["Content-Type"] = "application/json"
        HTTP::Request.new(method, resource, headers, body)
      else
        HTTP::Request.new(method, resource, headers)
      end
    end

    def get(path : String, query : URI::Params? = nil) : JSON::Any
      perform(build_request("GET", path, query))
    end

    def post(path : String, body : String? = nil) : JSON::Any
      perform(build_request("POST", path, body: body))
    end

    def patch(path : String, body : String? = nil) : JSON::Any
      perform(build_request("PATCH", path, body: body))
    end

    def put(path : String, body : String? = nil) : JSON::Any
      perform(build_request("PUT", path, body: body))
    end

    def delete(path : String) : JSON::Any
      perform(build_request("DELETE", path))
    end

    def paginate(path : String, query : URI::Params = URI::Params.new, *, per_page : Int32 = 100, max_pages : Int32? = nil) : Array(JSON::Any)
      query = query.dup
      query["per_page"] = per_page.to_s
      results = [] of JSON::Any
      page = 1
      loop do
        query["page"] = page.to_s
        chunk = get(path, query).as_a
        results.concat(chunk)
        break if chunk.size < per_page
        page += 1
        break if max_pages && page > max_pages
      end
      results
    end

    def rate_limit : JSON::Any
      get("/rate_limit")
    end

    def user : JSON::Any
      get("/user")
    end

    def user(login : String) : JSON::Any
      get("/users/#{login}")
    end

    def repo(owner : String, repo : String) : JSON::Any
      get("/repos/#{owner}/#{repo}")
    end

    def repos(*, per_page : Int32 = 30, page : Int32 = 1, sort : String? = nil, type : String? = nil) : Array(JSON::Any)
      params = paging(per_page, page)
      params["sort"] = sort if sort
      params["type"] = type if type
      get("/user/repos", params).as_a
    end

    def org_repos(org : String, *, per_page : Int32 = 30, page : Int32 = 1, type : String? = nil) : Array(JSON::Any)
      params = paging(per_page, page)
      params["type"] = type if type
      get("/orgs/#{org}/repos", params).as_a
    end

    def create_repo(name : String, *, description : String? = nil, private_repo : Bool = false, auto_init : Bool = false) : JSON::Any
      post("/user/repos", json_body do |json|
        json.field "name", name
        json.field "description", description if description
        json.field "private", private_repo
        json.field "auto_init", auto_init
      end)
    end

    def delete_repo(owner : String, repo : String) : Nil
      delete("/repos/#{owner}/#{repo}")
      nil
    end

    def branches(owner : String, repo : String, *, per_page : Int32 = 30, page : Int32 = 1) : Array(JSON::Any)
      get("/repos/#{owner}/#{repo}/branches", paging(per_page, page)).as_a
    end

    def tags(owner : String, repo : String, *, per_page : Int32 = 30, page : Int32 = 1) : Array(JSON::Any)
      get("/repos/#{owner}/#{repo}/tags", paging(per_page, page)).as_a
    end

    def commits(owner : String, repo : String, *, sha : String? = nil, path : String? = nil, per_page : Int32 = 30, page : Int32 = 1) : Array(JSON::Any)
      params = paging(per_page, page)
      params["sha"] = sha if sha
      params["path"] = path if path
      get("/repos/#{owner}/#{repo}/commits", params).as_a
    end

    def contents(owner : String, repo : String, path : String = "", *, ref : String? = nil) : JSON::Any
      params = URI::Params.new
      params["ref"] = ref if ref
      get("/repos/#{owner}/#{repo}/contents/#{path}", params)
    end

    def issues(owner : String, repo : String, *, state : String = "open", labels : String? = nil, per_page : Int32 = 30, page : Int32 = 1) : Array(JSON::Any)
      params = paging(per_page, page)
      params["state"] = state
      params["labels"] = labels if labels
      get("/repos/#{owner}/#{repo}/issues", params).as_a
    end

    def issue(owner : String, repo : String, number : Int32) : JSON::Any
      get("/repos/#{owner}/#{repo}/issues/#{number}")
    end

    def create_issue(owner : String, repo : String, title : String, *, body : String? = nil, labels : Array(String)? = nil, assignees : Array(String)? = nil) : JSON::Any
      post("/repos/#{owner}/#{repo}/issues", json_body do |json|
        json.field "title", title
        json.field "body", body if body
        json.field "labels", labels if labels
        json.field "assignees", assignees if assignees
      end)
    end

    def update_issue(owner : String, repo : String, number : Int32, *, title : String? = nil, body : String? = nil, state : String? = nil, labels : Array(String)? = nil, assignees : Array(String)? = nil) : JSON::Any
      patch("/repos/#{owner}/#{repo}/issues/#{number}", json_body do |json|
        json.field "title", title if title
        json.field "body", body if body
        json.field "state", state if state
        json.field "labels", labels if labels
        json.field "assignees", assignees if assignees
      end)
    end

    def close_issue(owner : String, repo : String, number : Int32) : JSON::Any
      update_issue(owner, repo, number, state: "closed")
    end

    def issue_comments(owner : String, repo : String, number : Int32, *, per_page : Int32 = 30, page : Int32 = 1) : Array(JSON::Any)
      get("/repos/#{owner}/#{repo}/issues/#{number}/comments", paging(per_page, page)).as_a
    end

    def comment_issue(owner : String, repo : String, number : Int32, body : String) : JSON::Any
      post("/repos/#{owner}/#{repo}/issues/#{number}/comments", json_body do |json|
        json.field "body", body
      end)
    end

    def pull_requests(owner : String, repo : String, *, state : String = "open", head : String? = nil, base : String? = nil, per_page : Int32 = 30, page : Int32 = 1) : Array(JSON::Any)
      params = paging(per_page, page)
      params["state"] = state
      params["head"] = head if head
      params["base"] = base if base
      get("/repos/#{owner}/#{repo}/pulls", params).as_a
    end

    def pull_request(owner : String, repo : String, number : Int32) : JSON::Any
      get("/repos/#{owner}/#{repo}/pulls/#{number}")
    end

    def create_pull_request(owner : String, repo : String, title : String, head : String, base : String, *, body : String? = nil, draft : Bool = false) : JSON::Any
      post("/repos/#{owner}/#{repo}/pulls", json_body do |json|
        json.field "title", title
        json.field "head", head
        json.field "base", base
        json.field "body", body if body
        json.field "draft", draft
      end)
    end

    def update_pull_request(owner : String, repo : String, number : Int32, *, title : String? = nil, body : String? = nil, state : String? = nil, base : String? = nil) : JSON::Any
      patch("/repos/#{owner}/#{repo}/pulls/#{number}", json_body do |json|
        json.field "title", title if title
        json.field "body", body if body
        json.field "state", state if state
        json.field "base", base if base
      end)
    end

    def close_pull_request(owner : String, repo : String, number : Int32) : JSON::Any
      update_pull_request(owner, repo, number, state: "closed")
    end

    def merge_pull_request(owner : String, repo : String, number : Int32, *, merge_method : String = "merge", commit_title : String? = nil) : JSON::Any
      put("/repos/#{owner}/#{repo}/pulls/#{number}/merge", json_body do |json|
        json.field "merge_method", merge_method
        json.field "commit_title", commit_title if commit_title
      end)
    end

    def releases(owner : String, repo : String, *, per_page : Int32 = 30, page : Int32 = 1) : Array(JSON::Any)
      get("/repos/#{owner}/#{repo}/releases", paging(per_page, page)).as_a
    end

    def latest_release(owner : String, repo : String) : JSON::Any
      get("/repos/#{owner}/#{repo}/releases/latest")
    end

    def release_by_tag(owner : String, repo : String, tag : String) : JSON::Any
      get("/repos/#{owner}/#{repo}/releases/tags/#{tag}")
    end

    def create_release(owner : String, repo : String, tag : String, *, title : String? = nil, body : String? = nil, target : String? = nil, draft : Bool = false, prerelease : Bool = false) : JSON::Any
      post("/repos/#{owner}/#{repo}/releases", json_body do |json|
        json.field "tag_name", tag
        json.field "name", title if title
        json.field "body", body if body
        json.field "target_commitish", target if target
        json.field "draft", draft
        json.field "prerelease", prerelease
      end)
    end

    def search_repositories(q : String, *, sort : String? = nil, order : String? = nil, per_page : Int32 = 30, page : Int32 = 1) : JSON::Any
      search("/search/repositories", q, sort, order, per_page, page)
    end

    def search_issues(q : String, *, sort : String? = nil, order : String? = nil, per_page : Int32 = 30, page : Int32 = 1) : JSON::Any
      search("/search/issues", q, sort, order, per_page, page)
    end

    def search_users(q : String, *, sort : String? = nil, order : String? = nil, per_page : Int32 = 30, page : Int32 = 1) : JSON::Any
      search("/search/users", q, sort, order, per_page, page)
    end

    def search_code(q : String, *, sort : String? = nil, order : String? = nil, per_page : Int32 = 30, page : Int32 = 1) : JSON::Any
      search("/search/code", q, sort, order, per_page, page)
    end

    private def search(path : String, q : String, sort : String?, order : String?, per_page : Int32, page : Int32) : JSON::Any
      params = paging(per_page, page)
      params["q"] = q
      params["sort"] = sort if sort
      params["order"] = order if order
      get(path, params)
    end

    private def paging(per_page : Int32, page : Int32) : URI::Params
      params = URI::Params.new
      params["per_page"] = per_page.to_s
      params["page"] = page.to_s
      params
    end

    private def json_body(&block : JSON::Builder ->) : String
      JSON.build do |json|
        json.object do
          block.call(json)
        end
      end
    end

    private def perform(request : HTTP::Request) : JSON::Any
      HTTP::Client.new(@api_url) do |client|
        response = client.exec(request)
        raise GitHubError.new(response.status, response.body) unless response.success?
        response.body.empty? ? JSON::Any.new(nil) : JSON.parse(response.body)
      end
    end
  end
end
