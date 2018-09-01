require 'sinatra/base'
require 'erubis'
require 'oj'

require_relative './redis'
require_relative './db'

module Ishocon2
  class AuthenticationError < StandardError;
  end
  class PermissionDenied < StandardError;
  end
end

class Ishocon2::WebApp < Sinatra::Base
  session_secret = ENV['ISHOCON2_SESSION_SECRET'] || 'showwin_happy'
  use Rack::Session::Cookie, key: 'rack.session', secret: session_secret
  set :erb, escape_html: true
  set :public_folder, File.expand_path('../public', __FILE__)
  set :protection, true

  VIEW_INDEX_KEY = 'view:index'.freeze
  VIEW_CANDIDATE_KEY = 'view:candidate'.freeze
  VIEW_POLITICAL_PARTY_KEY = 'view:political_party'.freeze

  configure :development do
    require 'sinatra/reloader'
    register Sinatra::Reloader

    require 'rack-mini-profiler'
    use Rack::MiniProfiler

    require 'rack-lineprof'
    use Rack::Lineprof, profile: 'app.rb'
  end

  helpers do
    def voice_of_supporter(candidate_ids)
      query = <<~SQL
        SELECT keyword
        FROM voices
        WHERE candidate_id IN (?)
        GROUP BY keyword
        ORDER BY SUM(count) DESC
        LIMIT 10
      SQL
      db.xquery(query, candidate_ids).map { |a| a[:keyword] }
    end

    def db_initialize
      db.query('DELETE FROM votes')
      db.query('DELETE FROM voices')
    end

    def redis_initialize
      redis.flushall
      store_candidates
      set_rendered_vote
      set_candidate_votes
      set_sex_votes
    end

    def store_candidates
      candidates = db.xquery('select * from candidates').to_a

      candidates.each do |candidate|
        redis.set("candidates:#{candidate[:id]}:data", Oj.dump(candidate))
      end
    end

    def set_rendered_vote
      redis.set('rendered_vote', erb(:vote, locals: { candidates: stored_candidates }))
    end

    def set_candidate_votes
      store_candidates.each do |c|
        redis.set candidate_vote_key(c), 0
      end
    end

    def set_sex_votes
      redis.set('man:vote', 0)
      redis.set('woman:vote', 0)
    end

    def candidate_vote_key(candidate)
      "party:#{candidate[:political_party]}:#{candidate[:id]}:vote"
    end

    def stored_parties
      %w(夢実現党 国民10人大活躍党 国民元気党 国民平和党)
    end

    def stored_candidates
      @candidates unless @candidates.nil?
      candidates_keys = redis.keys 'candidates:*:data'
      @candidates = redis.mget(candidates_keys).map { |data| Oj.load(data) }
    end

    def stored_candidate(id)
      key = "candidates:#{id}:data"
      Oj.load(redis.get(key))
    end

    def get_candidate_vote(candidate)
      redis.get("party:#{candidate[:political_party]}:#{candidate[:id]}:vote").to_i
    end

    def get_party_vote(party_name)
      candidates_keys = redis.keys "party:#{party_name}:*:vote"
      redis.mget(candidates_keys).map(&:to_i).sum
    end
  end

  get '/' do
    rendered_index = redis.get(VIEW_INDEX_KEY)
    return rendered_index if rendered_index

    # 候補者別の投票数
    candidates = []
    candidates_result = stored_candidates.map do |candidate|
      [candidate[:id], get_candidate_vote(candidate)]
    end
    sorted = candidates_result.sort { |a, b| a[1] <=> b[1] }.reverse
    sorted.slice(0...10).each do |res|
      candidate = stored_candidate(res[0])
      candidate[:count] = res[1]
      candidates << candidate
    end
    last_candidate_result = sorted.last
    if last_candidate_result
      candidate = stored_candidate(last_candidate_result[0])
      candidate[:count] = last_candidate_result[1]
      candidates << candidate
    end

    # 政党別の投票数
    parties = {}
    stored_parties.map { |party_name| parties[party_name] = get_party_vote(party_name) }

    # 性別の投票数
    man_votes = redis.get('man:vote').to_i
    woman_votes = redis.get('woman:vote').to_i
    sex_ratio = { '男': man_votes, '女': woman_votes }

    rendered_view = erb :index, locals: { candidates: candidates,
      parties: parties,
      sex_ratio: sex_ratio }


    if 200 < redis.get('votes').to_i
      redis.set(VIEW_INDEX_KEY, rendered_view)
      redis.expired(VIEW_INDEX_KEY, 30)
    end

    rendered_view
  end

  get '/candidates/:id' do
    rendered_index = redis.get(VIEW_CANDIDATE_KEY )
    return rendered_index if rendered_index

    candidate = stored_candidate(params[:id])
    return redirect '/' if candidate.nil?

    votes = get_candidate_vote(candidate)
    keywords = voice_of_supporter([params[:id]])

    rendered_view = erb :candidate, locals: { candidate: candidate,
      votes: votes,
      keywords: keywords }

    if 200 < redis.get('votes').to_i
      redis.set(VIEW_CANDIDATE_KEY , rendered_view)
      redis.expired(VIEW_CANDIDATE_KEY , 30)
    end

    rendered_view
  end

  get '/political_parties/:name' do
    rendered_index = redis.get(VIEW_POLITICAL_PARTY_KEY)
    return rendered_index if rendered_index

    votes = get_party_vote(params[:name])
    candidates = stored_candidates.select { |c| c[:political_party] == params[:name] }
    candidate_ids = candidates.map { |c| c[:id] }
    keywords = voice_of_supporter(candidate_ids)

    rendered_view = erb :political_party, locals: { political_party: params[:name],
      votes: votes,
      candidates: candidates,
      keywords: keywords }

    if 200 < redis.get('votes').to_i
      redis.set(VIEW_POLITICAL_PARTY_KEY, rendered_view)
      redis.expired(VIEW_POLITICAL_PARTY_KEY, 30)
    end

    rendered_view
  end

  get '/vote' do
    render_vote
  end

  post '/vote' do
    user = db.xquery('SELECT * FROM users WHERE name = ? AND address = ? AND mynumber = ?',
      params[:name],
      params[:address],
      params[:mynumber]).first

    return render_vote('個人情報に誤りがあります') if user.nil?
    return render_vote('候補者を記入してください') if params[:candidate].nil? || params[:candidate] == ''

    candidate = stored_candidates.find { |h| h[:name] == params[:candidate] }

    return render_vote('候補者を正しく記入してください') if candidate.nil?
    return render_vote('投票理由を記入してください') if params[:keyword].nil? || params[:keyword] == ''

    key = "user:#{user[:id]}:vote"

    redis.setnx(key, user[:votes])

    voted_count = redis.get(key).to_i
    voting_count = params[:vote_count].to_i

    return render_vote('投票数が上限を超えています') if voted_count < voting_count

    voice = db.xquery('SELECT * FROM voices WHERE candidate_id = ? AND keyword = ?', candidate[:id], params[:keyword]).first
    if voice
      db.xquery('UPDATE voices SET count = ? WHERE id = ?', voice[:count] + voting_count, voice[:id])
    else
      db.xquery('INSERT INTO voices (candidate_id, keyword, count) VALUES (?, ?, ?)', candidate[:id], params[:keyword], voting_count)
    end

    redis.incrby candidate_vote_key(candidate), voting_count

    if candidate[:sex] == '男'
      redis.incrby 'man:vote', voting_count
    else
      redis.incrby 'woman:vote', voting_count
    end

    redis.decrby key, voting_count

    redis.incr('votes')

    return render_vote('投票に成功しました')
  end

  def user_vote(key)
    user_vote = redis.get key
    if user_vote.nil?
      redis.set key, user[:votes]
      user_user[:votes]
    else
      user_vote.to_i
    end
  end

  def render_vote(message = '')
    rendered_vote_erb = redis.get('rendered_vote')
    rendered_vote_erb.sub("{{MESSAGE}}", message)
  end

  get '/initialize' do
    db_initialize
    redis_initialize
  end
end
